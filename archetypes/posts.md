+++
title = "{{ .TranslationBaseName | replaceRE "^[0-9]{4}-[0-9]{2}-[0-9]{2}-" "" | replaceRE "-" " " | title }}"
date = {{ .Date }}
draft = false
tags = []
projects = []
+++

*content*
