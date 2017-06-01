Instrument programs with QEMU
#############################

Pierrick Bouvier - STMicroelectronics/INRIA-CORSE

Antoine Moynault - STMicroelectronics

Lyon, 21 June 2017

-------------------------------------

QEMU
####

- A Fast and Portable Dynamic Translator
- Created by Fabrice Bellard (tcc, ffmpeg, pi computation, ...)
- Plugins (Credits @C.Vincent (ST), @C.Guillon (ST)) API to instrument code

-------------------------------------

QEMU
####

- Translates code from guest code (binary or system) to host code (cpu
  running QEMU)
- Uses an IR
- Provides system mode (full VM) or user mode (binary only)

-------------------------------------

QEMU Translation
################

- From guest code (binary arch) to IR
- Then, from IR to host code (cpu executing)
- QEMU performs register allocation, liveness analysis for each block translated

-------------------------------------

QEMU Translation
################

- Translate block of code each time it is met for the first time
- A block code starts/ends when a jump/branch instruction is met
- Several blocks can be chained once their are translated
- When jumping in the middle of existing block, a new one is translated (no
  reuse)

-------------------------------------

Plugins (existing)
##################

API allowing to execute code when:

- a new block is translated
- after block is translated
- an IR opcode is emitted
- an instruction is decoded
- various services (insert call to helper, modify generated code, ...)

-------------------------------------

Plugins API
###########

.. code:: C

    void after_gen_opc(const TCGPluginInterface *tpi,
                       const TPIOpCode *opcode);

    void pre_tb_helper_code_t(const TCGPluginInterface *tpi,
                              TPIHelperInfo info,
                              uint64_t address,
                              uint64_t data1,
                              uint64_t data2,
                              const TranslationBlock* tb);

    void cpus_stopped(const TCGPluginInterface *tpi);

    void tpi_init(TCGPluginInterface *tpi)

-------------------------------------

Plugins API (param)
###################

- receive special query from gdb (through maintenance packet)
- declare/read/write parameters in plugins
- activate/deactive plugin during execution

.. code:: C

    void tpi_init(TCGPluginInterface *tpi)
    {
        ...
        tpi_declare_param_int(tpi, "param_int",
                              &param_int, -42,
                              "This is an int param");
        tpi_declare_param_string(tpi, "param_string",
                                 &param_string, "Welcome!",
                                 "what a nice string");
        ...
    }

-------------------------------------

Plugins (available)
###################

- **dineroIV**: cache simulator
- **dyncount**: count instructions per type
- **dyntrace**: disassemble on the fly
- **ftrace**: trace entry/exit of functions
- **icount**: count instructions (with helper)
- **profile**: count instructions per function
- **trace**: print address of each TB

-------------------------------------

Tutorial
########

Let's build a plugin!

Please follow tutorial at: https://github.com/atos-tools/qemu-plugins-tutorial
