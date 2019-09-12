use v6.c;
unit module Compress::Zstd:ver<0.0.2>:auth<cpan:TIMOTIMO>;

use NativeCall;

sub handleError(size_t $retcode --> size_t) {
    if ZSTD_isError($retcode) {
        die ZSTD_getErrorName($retcode)
    }
    $retcode;
}

my sub ZSTD_isError(size_t) returns uint32 is native('zstd') { }
my sub ZSTD_getErrorName(size_t) returns Str is native('zstd') { }

my sub malloc(size_t $amount) is native(Str) returns CArray[uint8] { }
my sub free(CArray[uint8]) is native(Str) { }

role Zstd::Buffer {
    method recommended-size(--> size_t) { ... }

    multi method new(Int $bufsize = self.recommended-size) {
        #self.new(nativecast(Pointer[uint8], CArray[uint8].allocate($bufsize)));
        #self.new(CArray[uint8].allocate($bufsize + 128));
        self.new(malloc($bufsize + 1), $bufsize + 1);
    }
    multi method new(CArray[uint8] $buffer, $size = $buffer.elems - 1) {
        my $result = self.bless(
            size => $size,
            pos => 0);
        use nqp;
        nqp::bindattr(nqp::decont($result), self, '$!buffer', $buffer);
        $result;
    }
}

class Zstd::InBuffer does Zstd::Buffer is repr<CStruct> is rw is export {
    has CArray[uint8] $.buffer;
    has size_t $.size;
    has size_t $.pos;

    submethod BUILD(:$!size, :$!pos) { }

    sub ZSTD_CStreamInSize returns size_t is native('zstd') { }

    method recommended-size(--> size_t) { ZSTD_CStreamInSize }
    submethod DESTROY {
        free($!buffer);
    }
}

class Zstd::OutBuffer does Zstd::Buffer is repr<CStruct> is rw is export {
    has CArray[uint8] $.buffer;
    has size_t $.size;
    has size_t $.pos;

    submethod BUILD(:$!size, :$!pos) { }

    sub ZSTD_CStreamOutSize returns size_t is native('zstd') { }

    method recommended-size(--> size_t) { ZSTD_CStreamOutSize }

    submethod DESTROY {
        free($!buffer);
    }
}

class Zstd::CStream is repr<CPointer> is export {
    sub ZSTD_createCStream() returns Zstd::CStream is native('zstd') { }
    sub ZSTD_freeCStream(Zstd::CStream) returns size_t is native('zstd') { }
    sub ZSTD_initCStream(Zstd::CStream, int32 $level) returns size_t is native('zstd') { }

    sub ZSTD_compressStream(Zstd::CStream, Zstd::OutBuffer, Zstd::InBuffer) returns size_t is native('zstd') { }
    sub ZSTD_flushStream(Zstd::CStream, Zstd::OutBuffer) returns size_t is native('zstd') { }
    sub ZSTD_endStream(Zstd::CStream, Zstd::OutBuffer) returns size_t is native('zstd') { }

    # compression level 0 has the special meaning to use the default
    method new(int32 $level = 0) {
        my $cstr = ZSTD_createCStream;
        $cstr.&ZSTD_initCStream($level).&handleError;
        $cstr
    }
    submethod DESTROY {
        self.&ZSTD_freeCStream.&handleError
    }

    method feed-input(Zstd::InBuffer $in, Zstd::OutBuffer $out) {
        self.&ZSTD_compressStream($out, $in).&handleError;
    }

    method flush-stream(Zstd::OutBuffer $out) {
        self.&ZSTD_flushStream($out).&handleError
    }
    method end-stream(Zstd::OutBuffer $out) {
        self.&ZSTD_endStream($out).&handleError
    }
}

class Zstd::DStream is repr<CPointer> is export {
    sub ZSTD_createDStream() returns Zstd::DStream is native('zstd') { }
    sub ZSTD_freeDStream(Zstd::DStream) returns size_t is native('zstd') { }

    sub ZSTD_initDStream(Zstd::DStream) returns size_t is native('zstd') { }
    sub ZSTD_decompressStream(Zstd::DStream, Zstd::OutBuffer, Zstd::InBuffer) returns size_t is native('zstd') { }

    method new {
        my $dstr = ZSTD_createDStream;
        $dstr.&ZSTD_initDStream.&handleError;
        $dstr
    }
    submethod DESTROY {
        self.&ZSTD_freeDStream.&handleError
    }

    method feed-input(Zstd::InBuffer $in, Zstd::OutBuffer $out) {
        self.&ZSTD_decompressStream($out, $in).&handleError;
    }
}

class Zstd::Compressor {
    has Zstd::CStream $!cstream;
    has Zstd::InBuffer $!feedBuf;
    has Zstd::OutBuffer $!resBuf;

    has uint64 $!feedBufSize;
    has uint64 $!resBufSize;

    has buf8 $!compressorOutput;

    submethod BUILD(Zstd::InBuffer:D :$input-buffer = Zstd::InBuffer.new, Zstd::OutBuffer:D :$output-buffer = Zstd::OutBuffer.new) {
        $!cstream = Zstd::CStream.new;
        $!feedBuf = $input-buffer;
        $!resBuf  = $output-buffer;

        $!feedBufSize = $!feedBuf.size;
        $!resBufSize = $!resBuf.size;

        $!compressorOutput .= new;
    }

    method !transport-output {
        if $!resBuf.pos > 0 {
            $!compressorOutput.append($!resBuf.buffer[0 ..^ $!resBuf.pos].Array);
            $!resBuf.pos = 0;
            $!resBuf.size = $!resBufSize;

            # |---[=======]-------------|
            # ^ 0         ^ pos         ^ feedBufSize
            #     ^ prevPos
        }

    }

    method compress(blob8 $input) {
        if $input.elems {
            my $chunk = $input;
            my $output = buf8.new;
            while $chunk.elems() && $chunk.elems > $!feedBufSize {
               my $partial = $chunk.splice(0, $!feedBufSize);
               if $partial.elems() {
                   my $res = self.compress($partial);
               }
            }

            # Input buffer:
            # before compress:
            # |===========]-------------|
            # ^ pos       ^ size        ^ feedBufSize
            # 
            # pos is potentially ignored? better to zero it out always

            # after compress:
            # |-----| parts successfully compressed
            # |_____[=====]-------------|
            #       ^ pos ^ size        ^ feedBufSize
            #       |-----|
            #       ^ data left over (input stream over or output buffer full)

            my int $targetPos = 0;
            my int $targetElems = $input.elems;

            my CArray[uint8] $target := $!feedBuf.buffer;

            $target[$targetPos - 1] = $chunk[$targetPos - 1] while $targetPos++ <= $targetElems;

            $!feedBuf.size = $targetElems;
            $!feedBuf.pos = 0;

            $!cstream.feed-input($!feedBuf, $!resBuf);

            if $!feedBuf.pos == $!feedBuf.size {
                $!feedBuf.pos = 0;
                $!feedBuf.size = 0;
            }
            else {
                die "feeding more input when output buffer was full NYI";
            }
        }
        else {
            self.flush
        }

        self!transport-output;

        $!compressorOutput
    }

    method flush {
        $!cstream.flush-stream($!resBuf);

        self!transport-output;

        $!compressorOutput;
    }

    method end-stream {
        my $to-flush;
        repeat {
            $to-flush = $!cstream.end-stream($!resBuf);

            self!transport-output;
        } until ($to-flush == 0);

        $!compressorOutput;
    }
}

class Zstd::Decompressor {
    has Zstd::DStream $!dstream;
    has Zstd::InBuffer $!feedBuf;
    has Zstd::OutBuffer $!resBuf;

    has uint64 $!feedBufSize;
    has uint64 $!resBufSize;

    has buf8 $!decompressorOutput;

    has buf8 $!leftOvers;

    has int64 $!status;

    submethod BUILD(Zstd::InBuffer:D :$input-buffer = Zstd::InBuffer.new, Zstd::OutBuffer:D :$output-buffer = Zstd::OutBuffer.new) {
        $!dstream = Zstd::DStream.new;
        $!feedBuf = $input-buffer;
        $!resBuf  = $output-buffer;

        $!feedBufSize = $!feedBuf.size;
        $!resBufSize = $!resBuf.size;

        $!decompressorOutput .= new;
        $!leftOvers .= new;

        $!status = Zstd::InBuffer.recommended-size min $!feedBufSize;
    }

    sub memmove(CArray $target, Pointer $source, int32 $count) is native(Str) {*}

    method decompress(buf8 $input) {
        if $input.elems > 0 {
            my $chunk = $input;
            my $output = buf8.new;
            while $chunk.elems() && $chunk.elems > $!feedBufSize {
               my $partial = $chunk.splice(0, $!feedBufSize);
               if $partial.elems() {
                   my $res = self.decompress($partial);
               }
            }

            my int $targetPos = -1;
            my int $targetElems = $input.elems;

            my CArray[uint8] $target := $!feedBuf.buffer;

            use nqp;
            nqp::bindpos_i(nqp::decont($target), $targetPos, nqp::atpos_i(nqp::decont($chunk), $targetPos)) while ++$targetPos < $targetElems;

            $!feedBuf.size = $targetElems;
            $!feedBuf.pos = 0;

            $!status = $!dstream.feed-input($!feedBuf, $!resBuf);

            if $!feedBuf.pos == $!feedBuf.size {
                $!feedBuf.pos = 0;
                $!feedBuf.size = 0;
            }
            else {
                if $!status == 0 {
                    #$!leftOvers.append($!feedBuf.buffer[$!feedBuf.pos ..^ $input.elems].Array);
                    use nqp;
                    my int $pos = $!feedBuf.pos - 1;
                    my int $endPos = $input.elems - 1;
                    my $inBuf := $!feedBuf.buffer;
                    nqp::push_i(nqp::decont($!leftOvers), nqp::atpos_i($inBuf, $pos)) while $pos++ < $endPos;
                }
                else {
                    my $feedbuf-moved = 0;
                    loop {
                        my $fbb := $!feedBuf.buffer;
                        memmove($fbb, nativecast(Pointer[uint8], $fbb).add($!feedBuf.pos), $!feedBuf.size - $!feedBuf.pos);
                        $!feedBuf.size -= $!feedBuf.pos;
                        $feedbuf-moved += $!feedBuf.pos;
                        $!feedBuf.pos = 0;

                        self!transport-output;

                        $!status = $!dstream.feed-input($!feedBuf, $!resBuf);

                        if $!feedBuf.pos == $!feedBuf.size {
                            last
                        }
                        elsif $!status == 0 {
                            $!leftOvers.append($!feedBuf.buffer[$!feedBuf.pos ..^ ($input.elems - $feedbuf-moved)].Array);
                            last;
                        }

                    }
                }
            }

            self!transport-output
        }

        $!decompressorOutput;
    }

    method get-leftovers {
        $!leftOvers
    }

    method !transport-output {
        use nqp;
        if $!resBuf.pos > 0 {
            my int $resbufpos = -1;
            my int $targetpos = $!resBuf.pos - 1;
            my $buf := nqp::decont($!resBuf.buffer);
            nqp::push_i(nqp::decont($!decompressorOutput), nqp::atpos_i($buf, $resbufpos)) while $resbufpos++ < $targetpos;
            $!resBuf.pos = 0;
            $!resBuf.size = $!resBufSize;

            # |---[=======]-------------|
            # ^ 0         ^ pos         ^ feedBufSize
            #     ^ prevPos
        }
    }

    method finished-a-frame {
        $!status == 0
    }
    method suggested-next-size {
        $!status || 40960
    }
}

=begin pod

=head1 NAME

Compress::Zstd - Native binding to Facebook's Zstd compression library

=head1 SYNOPSIS

=begin code :lang<perl6>

use Compress::Zstd;

my $compressor = Zstd::Compressor.new;

$comp.compress("hello how are you today?".encode("utf8"));
my $result = $comp.end-stream;
"/tmp/compressed.zstd".IO.spurt($result);

$result.append("here is some bonus junk at the end".encode("utf8"));

my $decompressor = Zstd::Decompressor.new;

my $decomp-result = $decompressor.decompress($result);

my $the-junk-at-the-end-again = $decompressor.get-leftovers;

=end code

=head1 DESCRIPTION

Compress::Zstd lets you read and write data compressed with facebook's zstd library.

The API is not yet stable and may receive some improvements and/or clarifications in future versions.

=head1 AUTHOR

Timo Paulssen <timonator@perpetuum-immobile.de>

=head1 COPYRIGHT AND LICENSE

Copyright 2019 Timo Paulssen

This library is free software; you can redistribute it and/or modify it under the Artistic License 2.0.

=end pod
