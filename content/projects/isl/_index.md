+++
title = "Ironic Space Lisp"
+++

In order to meet some particular requirements for a separate project, I began
development on a new programming language based on Lisp and Erlang. Some of the
requirements were that the entire environment be pausable and serializable, and
contain deep hooks and callbacks to allow the host program to dynamically
control fundamental aspects of evaluation. The interpreter is currently under
development in Rust.
