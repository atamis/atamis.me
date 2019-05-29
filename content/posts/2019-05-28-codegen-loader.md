---
title: "Codegen Loader"
date: 2019-05-28T17:04:04-07:00
---

In what is very likely an enormously bad idea, I have built a JVM classloader
that can load dynamically load Java source files into memory.


# Why

I've recently been going "Full Juxt", using all of Juxt's Clojure libraries,
specifically [`juxt/aero`](https://github.com/juxt/aero) for configuration,
[`juxt/bidi`](https://github.com/juxt/bidi) for routing,
[`juxt/yada`](https://github.com/juxt/yada) for endpoint handling,
[`weavejester/integrant`](https://github.com/weavejester/integrant) for
"building applications" (probably dependency injection),
[`juxt/joplin`](https://github.com/juxt/joplin) for database migrations,  and
[`juxt/edge`](https://github.com/juxt/edge) to tie it all together.



All of Juxt's libraries are relentlessly data focused, and use `deps.edn` for
dependency management and application launching.

The problem I've encountered is Java interop with `deps.edn`. `deps.edn` _only_
loads Clojure code. So if I want to use Java, what do I do?[^1] Do I manually
compile my Java source? Do I abandon `deps.edn` in favor of a build system, like
Boot, Gradle, or Leiningen? No. Let's compile the Java at runtime, and
distribute raw Java source files next to our Clojure source files. What are the
implications of this decision? Is the rest of the ecosystem even ready for
uncompiled Java source in Jars? Don't know, don't care. Let's go.

# Compilation and Capture

So our goal, for now, is to be able to load `.java` source files from the class
path and compile them to `.class` definitions in memory. Ideally, we would avoid
leaving detritus on the filesystem, particularly leaving `.class` files lying
around _on the classpath_, because that's a recipe for deep confusion.
We also want to do this in pure Clojure to avoid a chicken and egg problem of
needing to load a native-Java classloader in order to load Java files
in the first place. It turns out this is reasonably easy, thanks to [this
gist][this-gist].

This process works best if your compiler takes a classname rather than a path,
as it's entirely classpath based. You can get your local Java compiler pretty
easily with:

```Clojure
  (javax.tools.ToolProvider/getSystemJavaCompiler)
```

The Java compiler is _reasonably_ flexible about compilation, but it still has a
file-and-directory based understanding of code. This means that it's possible to
do the kind of chicanery we want to do, but the compiler isn't really ready for
it, so we have to do some slight of hand. The compiler isn't as simple as a
function from Java source to JVM bytecode, its input and output is more
complicated, and because it's Java, it's all hidden in classes and implicit
state.

So, we need to be able to capture the compiler's bytecode output, and prevent it
from reaching the filesystem. This is possible through the compiler's
`JavaFileManager`, an interface between the compiler and the filesystem. Because
the compiler always constructs its own file manager, we can't construct our own,
we have to inject a delegation object instead. Luckily, they've already written
one called the `ForwardingJavaFileManager`, which we can just subclass, make our
changes, and then pass it to the compiler, which happily lets us temporarily
inject a new concept of files into it for any particular compilation.

You can get the standard file manager with:

```Clojure
    (.getStandardFileManager compiler nil nil nil)
```

and we'll use a Clojure proxy to override some of its behavior.

```Clojure
(defn output-capture-file-manager
  "Creates an output capturing memory backed forwarding file manager. See
  ForwardingJavaFileManager for more details."
  [file-manager]
  (let [outputs (atom {})
        proxy (proxy [ForwardingJavaFileManager] [file-manager]
                (getJavaFileForOutput [location className kind sibling]
                  (let [output-file (make-mem-file className kind)]
                    (swap! outputs assoc className output-file)
                    output-file)))]
    [outputs proxy]))
```

Let's break this down. The `proxy` is a proxy to `ForwardingJavaFileManager`,
and it passes in the existing file manager, allowing our super class to properly
delegate.

```Clojure
        proxy (proxy [ForwardingJavaFileManager] [file-manager]
```

The only method we override is `getJavaFileForOutput`, which the
compiler calls to get a file for output. Rather than interact with the normal
filesystem, we use a function called `make-mem-file` (which we'll discuss later)
to provide a memory backed file instead.

```Clojure
                (getJavaFileForOutput [location className kind sibling]
                  (let [output-file (make-mem-file className kind)]
```

We capture the file in an atom of outputs for later use, and return it. The atom
is a mapping between class names and references to the `JavaFileObject` the
compiler expects, and because we're living in the Java world, we can use that
reference to get the compiler's output later.

```Clojure
                    (swap! outputs assoc className output-file)
```

Then we return the outputs atom and the new file manager.

Let's take a look at `make-mem-file`.

```Clojure
(defn make-mem-file
  "Creates a new SimpleJavaFileObject for a classname and
  kind with the uri mem:/// backed by a memory buffer
  (a ByteArrayOutputStream). "
  [class-name kind]
  (let [os (ByteArrayOutputStream.)
        new-cn (URI/create (str "mem:///"
                                (string/replace class-name "." "/")
                                (.extension kind)))]
    (proxy [SimpleJavaFileObject] [new-cn kind]
      (openOutputStream [] os))))
```

We convert the class name to a reasonable URI with the `mem://` "protocol", and
make normal `SimpleJavaFileObject` proxy that returns a byte array backed output
stream, which we can later read to get the file's contents back.

Putting these 2 proxies and callbacks together, we get a file manager that reads
source files normally, but captures output files and makes sure they're easily
findable and readable.

Back to the compiler, we need to get the "compilation unit", or the
`JavaFileObject` for the source we need to compile.

```Clojure
        (.getJavaFileForInput file-manager StandardLocation/CLASS_PATH classname
                                   javax.tools.JavaFileObject$Kind/SOURCE)
```

`classname` is the parameter, and `file-manager` is our own memory-backed file
manager. `StandardLocation` and `JavaFileObject.Kind` are enums that took some
experimenting to get right, because they're not particularly transparent about
the values they actually represent. `Kind/SOURCE` pretty clearly refers to
`.java`, but I couldn't figure out how to translate `StandardLocations` to file
paths, so I tried `SOURCE_PATH` before `CLASS_PATH`, which didn't work at all,
but `CLASS_PATH` did, and is also the path that Clojure loads source from, and
Clojure largely ignores the stereotypical compilation phase, and prefers to only
deal with the class path, which seems reasonable for this project.

Finally, we can actually do the compilation:

```Clojure
        task (.getTask compiler         ; compiler
                       nil              ; writer out
                       file-manager     ; file manager
                       nil              ; diagnostic listener
                       nil              ; options
                       nil              ; classes for annotations
                       [file]           ; compilation units
                       )
        _ (.call task)
```

This is a task we can await for the end of the compilation, but it doesn't
return anything concrete. The Java compiler has just left the compiled bytecode
where it generated it in the file manager. We'll have to read our atom to get
the bytecode, but that's a problem for our caller, so we just return the outputs
atom and the file manager. Putting it all together:

```Clojure
(defn java-compile
  "Compiles the class at classname, and returns an atom-wrapped mapping of
  output file names to SimpleFileObjects. By calling

       (.toByteArray (.openOutputStream file))

  You can get the byte contents of the compiled Java class."
  [classname]
  (let [compiler (javax.tools.ToolProvider/getSystemJavaCompiler)
        [outputs file-manager] (output-capture-file-manager (.getStandardFileManager compiler nil nil nil))
        ;; This is nil if the file wasn't found.
        file (.getJavaFileForInput file-manager StandardLocation/CLASS_PATH classname
                                   javax.tools.JavaFileObject$Kind/SOURCE
                                   )
        task (.getTask compiler         ; compiler
                       nil              ; writer out
                       file-manager     ; file manager
                       nil              ; diagnostic listener
                       nil              ; options
                       nil              ; classes for annotations
                       [file]           ; compilation units
                       )
        _ (.call task)]
    [outputs file-manager]))
```

And there you have it! Largely in-memory Java source compilation. Fully in
memory source compilation would require a little more work with the file
manager, but nonetheless, this is what we're looking for.

# The Classloader

This is where the problems start. You'd think that compiling would be the hard
part, but no, it's the class loader. The heart of the whole project is the fact
that Java gives us the ability to load raw bytecode class definitions directly
regardless of where the bytes come from. By default they read from an
environment-set classpath, or they read from jars, or whatever. This is enabled
by a method called `defineClass(String name, byte[] b, int off, int len)`, which
loads JVM bytecode and returns a `Class` object for the newly created class.
Unfortunately, `defineClass` is `protected` and `final` on the default
Classloader, which means that
Clojure can't call it. Even if you use `gen-class`, it can't call `defineClass`
from any subclasses, or from outside a classloader. I got around this by
subclassing `clojure.lang.DynamicClassLoader` instead, but this obviously has
additional consequences that I don't understand, and I can't set it as the
context loader, it gets unset immediately for reasons I don't understand.

```Clojure
(defn codegen-classloader
  "Returns a class loader that can dynamically compile Java classes as
  necessary."
  []
  (proxy [clojure.lang.DynamicClassLoader] []
    (findClass [classname]
      (let [[outputs _] (java-compile classname)]
        (if-let [class-file (@outputs classname)]
          (let [buffer (-> class-file .openOutputStream .toByteArray)]
            (proxy-super defineClass classname buffer nil)
            )
          (proxy-super findClass classname))))))
```

This overrides `findClass` and it always attempts to compile a class before
delegating to the superclass. This uses a slightly different kind of
`defineClass` that happens to be public.

This doesn't work very well for internal classes. Although the Java compiler
correctly outputs multiple `.class` files, this code is not well prepared to
deal with that complexity. It also doesn't share outputs between compilations,
which _I think_ means that everything gets recompiled every time, which is
clearly subpar.

A full treatment for this problem (has likely already been done even if I
couldn't find it) would maintain the same file manager and Java compiler.
However, my knowledge of the arcane internals of the JVM is lacking, so it's not
clear to me exactly how `ClassLoaders` are supposed to function. Most of the
articles I could find talk about classloader hierarchies as defined through
subclassing, and if you're writing a custom classloader, and you can't load a
particular class, you should call your superclass to help out. However,
Clojure's classloader is directly parameterized with a _parent classloader_, a
separate object it delegates to when it can't find or load a class. Exactly how
classloaders should work and are used by the JVM is not entirely clear to me,
and it's obvious that a poorly written classloader will seriously screw with the
JVM, not to mention that Clojure is seriously hampered in its ability to
implement classloaders in native Clojure thanks to the limitations of the
reflection API, so the entire project is kind of broken in the first place.

That's probably for the best, because "if you build it, they will come", and I
really don't want to _encourage_ people to use this outside its incredibly
narrow use case. Dynamically compiling missing classes sounds like something
that people have considered and discarded as a really bad idea. Still, it was a
fascinating truly misguided dive into the internals of the JVM. You can find the
code at [`atamis/codegen-loader`](https://github.com/atamis/codegen-loadenoiser)


[^1]: In truth, my problem was slightly complex, and the Java file lived in a
    Clojure project that wasn't published to a Maven repository, and I don't
    like local install as part of the development process, so I wanted to use
    `:local/root` or git dependencies, which leaves me in the same situation.
    My first solution, found in [`noise`](https://github.com/atamis/noise), was
    to commit compiled binary to source control, which is obviously a bad idea,
    but it works!

[this-gist]: https://gist.github.com/chrisvest/9873843
