=====================
QEMU plugins tutorial
=====================

Environment
===========

Setup
-----

Without docker
++++++++++++++

- Install dependencies on your machine

.. code:: shell

    apt update &&
    apt build-dep -y qemu &&
    apt install -y libcapstone-dev git

With docker
+++++++++++

- Install docker: https://docs.docker.com/engine/installation/

- Get our image or build it from Dockerfile (see commands below)

- If you work with docker:

    - build and run from inside container (work directory will be mounted
      inside your container).
    - edit files from outside in your host rootfs (with your favorite editor).
    - More simply: keep one terminal inside your container and another to edit
      your files. 

- Docker commands to load/run existing image

.. code:: shell

    # to load docker image from archive
    docker load < docker_tutorial_qemu.tar.xz
    # to enter docker container, use:
    docker run -it --rm=true -u $UID -v $PWD:$PWD -w $PWD tutorial:qemu bash

- Docker commands to build image

.. code:: shell

    # clone this repo
    git clone https://github.com/atos-tools/qemu-plugins-tutorial
    cd qemu-plugins-tutorial
    # build your image from Dockerfile
    docker build -t tutorial:qemu - < Dockerfile
    # if you want to export it, save image as a compressed file
    docker save tutorial:qemu | xz > docker_tutorial_qemu.tar.xz

Build
-----

Get sources

.. code:: shell

    # from your host
    # get sources from git
    git clone https://github.com/atos-tools/qemu --branch next/master --depth 1
    # or from our file
    # tar xvf qemu_src.tar.xz
    cd qemu

    # now switch to docker container
    docker run -it --rm=true -u $UID -v $PWD:$PWD -w $PWD tutorial:qemu bash

    # configure project
    ./configure --enable-capstone --enable-tcg-plugin --target-list=x86_64-linux-user
    # build
    make -j4
    # test cache plugin with ls
    ./x86_64-linux-user/qemu-x86_64 --tcg-plugin dineroIV /bin/ls

Run
---

.. code:: shell

    ./x86_64-linux-user/qemu-x86_64 --tcg-plugin plugin_name /path/to/bin

QEMU code
=========

Plugins
-------

QEMU plugins sources are located in ``tcg/plugins``

The QEMU plugins API
--------------------

A detailed introduction is available in ``tcg/plugins/README``

.. code:: C

    /* called after generation of each QEMU opcode */
    void after_gen_opc(const TCGPluginInterface *tpi,
                       const TPIOpCode *opcode);

    /* function called at the beginning of each translation block */
    void pre_tb_helper_code_t(const TCGPluginInterface *tpi,
                              TPIHelperInfo info,
                              uint64_t address,
                              uint64_t data1,
                              uint64_t data2,
                              const TranslationBlock* tb);

    /* set data passed to previous helper */
    void pre_tb_helper_data(const TCGPluginInterface *tpi,
                            TPIHelperInfo info, uint64_t address,
                            uint64_t *data1, uint64_t *data2,
                            const TranslationBlock* tb);

    /* called at exit */
    void cpus_stopped(const TCGPluginInterface *tpi);

    /* called to initialize plugin */
    void tpi_init(TCGPluginInterface *tpi)

Tutorial
========

Objective
---------

For this tutorial, you will build a coverage plugin:

::

    // symbol __pthread_cleanup_pop_restore
    6 | 0x40016acb30:         mov     rax, qword ptr [rdi + 0x18]
    6 | 0x40016acb34:         mov     qword ptr fs:[0x2f8], rax
    6 | 0x40016acb3d:         mov     eax, dword ptr [rdi + 0x10]
    6 | 0x40016acb40:         test    eax, eax
    6 | 0x40016acb42:         jne     0x40016acb60
    6 | 0x40016acb44:         test    esi, esi
    6 | 0x40016acb46:         jne     0x40016acb50
    6 | 0x40016acb48:         ret
    0 | 0x40016acb4a:         nop     word ptr [rax + rax]
    0 | 0x40016acb50:         mov     rdx, qword ptr [rdi + 8]

For each known function (where symbol name is available), we print its assembly
listing with hit count for each instruction.

Coverage plugin (existing) is in ``tcg/plugins/coverage.c``.

To disassemble code, we use capstone library. For structures/containers, we use
glib.

Plugin structure
----------------

For each instruction translated, we keep a mapping between its address and the
number of time it was hit.

When instruction is translated, we insert a call to a function that increments
the hit counter.

Finally, for each function we hit (whose symbol was found), we disassemble it
and print the hit count.

Code
----

You can create a new plugin named coverage-tiny by reading and copy/pasting
following code. Existing coverage plugin is a bit more complex, but you can look
at the code as well.

First, edit file ``Makefile.target``, search for 'tcg-plugin-coverage:', add:

.. code:: Makefile

    tcg-plugin-coverage-tiny.o: CFLAGS += $(CAPSTONE_CFLAGS)
    tcg-plugin-coverage-tiny.so: LIBS += $(CAPSTONE_LDFLAGS)

Then you can edit ``tcg/plugin/coverage-tiny.c`` with following code.

//We start with classic includes

.. code:: C

    #include <stdint.h>

    /* tcg plugin include */
    #include "tcg-plugin.h"
    #include "disas/disas.h" /* lookup symbol */

    /* disassemble library */
    #include <capstone.h>

//Then some global variables and structures

.. code:: C

    static GHashTable *symbol_table; /* symbol_name -> address/size */

    static GHashTable *address_table; /* instr address -> count */

    struct symbol_table_entry
    {
        uint64_t symbol_address;
        uint64_t symbol_size;
    };

    struct address_table_entry
    {
        uint64_t count;
    };

//Our callbacks declaration.

.. code:: C

    /* to be called when instruction is hit */
    static void hit_instruction(int64_t count_ptr);

    /* callback for each opcode generated */
    static void after_gen_opc(const TCGPluginInterface *tpi,
                              const TPIOpCode *tpi_opcode);

    /* callback to report the coverage at exit */
    static void cpus_stopped(const TCGPluginInterface *tpi);

//Plugin initialize function.

.. code:: C

    void tpi_init(TCGPluginInterface *tpi)
    {
        /* initialize tpi struct */
        TPI_INIT_VERSION_GENERIC(tpi);
        /* declare a helper to be able to insert call to hit_instruction
        function directly inside a TranslationBlock */
        TPI_DECL_FUNC_1(tpi, hit_instruction, void, i64);

        /* register callbacks */
        tpi->after_gen_opc  = after_gen_opc;
        tpi->cpus_stopped = cpus_stopped;

        /* initialize global tables */
        symbol_table = g_hash_table_new_full(
            g_str_hash, g_str_equal, g_free, g_free);
        address_table = g_hash_table_new_full(
            g_direct_hash, g_direct_equal, NULL, g_free);
    }

//Function to execute when instruction is hit

.. code:: C

    static void hit_instruction(int64_t count_ptr)
    {
        (*(uint64_t*)count_ptr)++;
    }

//Callback when a new opcode is generated

.. code:: C

    static void after_gen_opc(const TCGPluginInterface *tpi,
                              const TPIOpCode *tpi_opcode)
    {
        const char *symbol = NULL;
        const char *filename = NULL;
        uint64_t symbol_address = 0;
        uint64_t symbol_size = 0;

        /* execute this callback only per translated instruction (that may
           result in several opcodes). We detect a special value for it. */
        if (tpi_opcode->operator != INDEX_op_insn_start)
            return;

        /* check if instruction address pc is inside a known symbol.
           If not, return */
        if (!lookup_symbol4(
                tpi_opcode->pc, &symbol, &filename, &symbol_address, &symbol_size)
            || symbol[0] == '\0')
            return;

        /* check if we met this symbol already */
        struct symbol_table_entry *symbol_table_entry =
            g_hash_table_lookup(symbol_table, symbol);
        if (symbol_table_entry == NULL) {
            /* create an entry for this symbol */
            symbol_table_entry = g_new(struct symbol_table_entry, 1);
            symbol_table_entry->symbol_address = symbol_address;
            symbol_table_entry->symbol_size = symbol_size;
            g_hash_table_insert(symbol_table, g_strdup(symbol), symbol_table_entry);
        }

        /* same for hit count */
        uint64_t *address_table_key = (uint64_t *)tpi_opcode->pc;
        struct address_table_entry *address_table_entry = g_hash_table_lookup(
            address_table, address_table_key);
        if (address_table_entry == NULL) {
            address_table_entry = g_new(struct address_table_entry, 1);
            /* initialize count to 0 */
            address_table_entry->count = 0;
            g_hash_table_insert(
                address_table, address_table_key, address_table_entry);
        }

        /* generate call to hit instruction directly with pointer on count */
        TCGArg args[] = {
            GET_TCGV_I64(tcg_const_i64((uint64_t)&address_table_entry->count)) };
        tcg_gen_callN(tpi->tcg_ctx, hit_instruction, TCG_CALL_DUMMY_ARG, 1, args);
    }

//Now display the final result

.. code:: C

    /* iterate on symbols met and print result */
    static void output_symbol_coverage(gpointer key,
                                       gpointer value,
                                       gpointer user_data);

    /* called at program exit */
    static void cpus_stopped(const TCGPluginInterface *tpi)
    {
        csh cs_handle;

        /* initialize capstone */
        if (cs_open(CS_ARCH_X86, CS_MODE_64, &cs_handle) != CS_ERR_OK)
            abort();
        cs_option(cs_handle, CS_OPT_DETAIL, CS_OPT_ON);

        void* data[] = {(void*)tpi, (void*)cs_handle};
        /* output coverage for each symbol */
        g_hash_table_foreach(symbol_table, output_symbol_coverage, data);

        // clean everything
        g_hash_table_destroy(symbol_table);
        g_hash_table_destroy(address_table);

        cs_close(&cs_handle);
    }

    static void output_symbol_coverage(gpointer key,
                                       gpointer value,
                                       gpointer user_data)
    {
        void** data = (void**)user_data;
        const TCGPluginInterface *tpi = (const TCGPluginInterface *)data[0];
        csh cs_handle = (csh)data[1];
        const char *symbol = (const char *)key;
        struct symbol_table_entry *symbol_entry = value;
        FILE *output = tpi->output;

        /* retrieve pointer on original code to disassemble it */
        const uint8_t *code = (const uint8_t *)(intptr_t)tpi_guest_ptr(
                                tpi, symbol_entry->symbol_address);
        size_t size = symbol_entry->symbol_size;
        uint64_t address = symbol_entry->symbol_address;

        fprintf(output, "// symbol %s\n", symbol);

        /* alloc instruction */
        cs_insn *insn = cs_malloc(cs_handle);
        /* start disassemble */
        while (cs_disasm_iter(cs_handle, &code, &size, &address, insn)) {
            /* retrieve hit count for this instruction */
            struct address_table_entry *value =
                g_hash_table_lookup(address_table, (uint64_t *)insn->address);
            uint64_t count = value ? value->count : 0;
            /* output instruction and count */
            fprintf(output, "%8" PRIu64 " | 0x%"PRIx64":\t %s\t %s\n",
                    count,
                    insn->address,
                    insn->mnemonic,
                    insn->op_str
                    );
        }
        cs_free(insn, 1);
    }

Try it
------

Why not use your plugin directly to cover qemu itself?

.. code:: shell

    ./x86_64-linux-user/qemu-x86_64 --tcg-plugin coverage-tiny ./x86_64-linux-user/qemu-x86_64 /bin/false
    # you can try coverage plugin as well
    ./x86_64-linux-user/qemu-x86_64 --tcg-plugin coverage ./x86_64-linux-user/qemu-x86_64 /bin/false |& less -R

To go further
-------------

- Write small code example to see coverage for it.
- Try to map assembly to source code.
- You can read code of other plugins, or write a new one from scratch!

References
----------

- glib data types: https://developer.gnome.org/glib/stable/glib-data-types.html
- capstone disassembler tools doc: http://www.capstone-engine.org/iteration.html
- qemu-plugins repository (branch next/master): https://github.com/atos-tools/qemu

Slides
------

You need to have ``pandoc`` installed to build slides.

.. code:: shell

    # need pandoc installed
    # apt install pandoc
    make -C slides
    # see slides with browser
    firefox slides/build/qemu_plugins.html
