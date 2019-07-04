[![Build Status](https://travis-ci.org/timo/Compress-Zstd.svg?branch=master)](https://travis-ci.org/timo/Compress-Zstd)

NAME
====

Compress::Zstd - Native binding to Facebook's Zstd compression library

SYNOPSIS
========

```perl6
use Compress::Zstd;

my $compressor = Zstd::Compressor.new;

$comp.compress("hello how are you today?".encode("utf8"));
my $result = $comp.end-stream;
"/tmp/compressed.zstd".IO.spurt($result);

$result.append("here is some bonus junk at the end".encode("utf8"));

my $decompressor = Zstd::Decompressor.new;

my $decomp-result = $decompressor.decompress($result);

my $the-junk-at-the-end-again = $decompressor.get-leftovers;
```

DESCRIPTION
===========

Compress::Zstd lets you read and write data compressed with facebook's zstd library.

The API is not yet stable and may receive some improvements and/or clarifications in future versions.

AUTHOR
======

Timo Paulssen <timonator@perpetuum-immobile.de>

COPYRIGHT AND LICENSE
=====================

Copyright 2019 Timo Paulssen

This library is free software; you can redistribute it and/or modify it under the Artistic License 2.0.

