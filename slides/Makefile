SRC = $(wildcard *.rst)
PRES = $(SRC:%.rst=build/%.html)

all: $(PRES)

build/reveal.js:
	rm -rf build/reveal.js
	mkdir -p build/
	git clone --depth=1 https://github.com/hakimel/reveal.js/ build/reveal.js

build/%.html: %.rst build/reveal.js
	mkdir -p build/
	pandoc $< \
		-o $@ \
		-t revealjs \
		-V theme:league \
		--self-contained -V revealjs-url:build/reveal.js
	sed -e "s/Reveal.initialize({/Reveal.initialize({\nslideNumber: 'c\/t',/" \
		-i $@

clean:
	rm -rf build
