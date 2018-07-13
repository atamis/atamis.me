# https://blog.bramp.net/post/2015/08/01/hugo-makefile/

.PHONY: all clean minified server watch help

HUGO := hugo
HTML_MINIFIER := html-minifier -c html-minifier.conf

# All input files
FILES=$(shell find content layouts static themes -type f)

# Below are PHONY targets
all: public minified

help:
	@echo "Usage: make <command>"
	@echo "  all     Builds the blog and minifies it"
	@echo "  clean   Cleans all build files"
	@echo "  server  Runs a webserver on port 1313 to test the final minified result"
	@echo "  watch   Runs hugo in watch mode, waiting for changes"
	@echo ""
	@echo "New article:"
	@echo "  hugo new post/the_title"
	@echo "  $$EDITOR content/post/the_title.md"
	@echo "  make watch"
	@echo "  open "

clean:
	-rm -rf public
	-rm .minified

minified: .minified

server: public
	cd public && python -m SimpleHTTPServer 1313

watch: clean
	$(HUGO) server -w

# Below are file based targets
public: $(FILES) config.yaml
	$(HUGO)

	# Post process some files (to make the HTML more bootstrap friendly)
	# Add a table class to all tables
	grep -IR --include=*.html --null -l -- "<table" public/ | xargs -0 sed -i '' 's/<table/<table class="table"/g'

	# Replace "align=..."" with class="test-..."
	grep -IR --include=*.html --null -l -- "<th" public/ | xargs -0 sed -i '' 's/<th align="/<th class="text-/g'
	grep -IR --include=*.html --null -l -- "<td" public/ | xargs -0 sed -i '' 's/<td align="/<td class="text-/g'

	# Ensure the public folder has it's mtime updated.
	touch $@

.minified: public html-minifier.conf
	# Find all HTML and in parallel run the minifier
	find public -type f -iname '*.html' | parallel --tag $(HTML_MINIFIER) "{}" -o "{}"
	touch .minified
