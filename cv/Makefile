.PHONY: clean

LATEXMK=/usr/bin/latexmk
PDFLATEX=/usr/bin/pdflatex --file-line-error --shell-escape -interaction=nonstopmode
LATEXMK_OPTS=-pdf -pdflatex="$(PDFLATEX)"

LONGNAME="Azrea Amis CV.pdf"

FILES=$(*.tex *.cls *.sty)

all: main.pdf
	cp main.pdf $(LONGNAME)

main.pdf: main.tex
	$(LATEXMK) $(LATEXMK_OPTS)  $<

clean:
	rm main.pdf $(LONGNAME)
