# https://blog.bramp.net/post/2015/08/01/hugo-makefile/

.PHONY: all clean watch help cv deploy

HUGO := hugo

# All input files
FILES=$(shell find content layouts static themes -type f)

# Below are PHONY targets
all: public

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
	-make -C cv clean

server: public
	cd public && python -m SimpleHTTPServer 1313

watch: clean
	$(HUGO) server -w

cv:
	make -C cv
	cp cv/main.pdf static/downloads/resume.pdf

# Below are file based targets
public: $(FILES) cv config.toml
	git submodule update --recursive
	$(HUGO)

	# Post process some files (to make the HTML more bootstrap friendly)
	# Add a table class to all tables
	#grep -IR --include=*.html --null -l -- "<table" public/ | xargs -0 sed -i '' 's/<table/<table class="table"/g'

	# Replace "align=..."" with class="test-..."
	#grep -IR --include=*.html --null -l -- "<th" public/ | xargs -0 sed -i '' 's/<th align="/<th class="text-/g'
	#grep -IR --include=*.html --null -l -- "<td" public/ | xargs -0 sed -i '' 's/<td align="/<td class="text-/g'

	# Ensure the public folder has it's mtime updated.
	touch $@


# https://gohugo.io/hosting-and-deployment/hosting-on-github/#build-and-deployment
deploy:
	@echo "Deleting old publication"
	make clean

	mkdir public
	git worktree prune

	@echo "Checking out gh-pages branch into public"
	git worktree add -B gh-pages public origin/gh-pages


	@echo "Removing existing files"
	rm -rf public/*

	make public

	@echo "Updating gh-pages branch"
	cd public && git add --all && git commit -m "Publishing to gh-pages `date` (Makefile)"
	cd ..
