use v6.c;
unit module Compress::Zstd:ver<0.0.1>:auth<cpan:TIMOTIMO>;

use NativeCall;

sub handleError(size_t $retcode --> size_t) {
    if ZSTD_isError($retcode) {
        die ZSTD_getErrorName($retcode)
    }
    $retcode;
}

my sub ZSTD_isError(size_t) returns uint32 is native('zstd') { }
my sub ZSTD_getErrorName(size_t) returns Str is native('zstd') { }

role Zstd::Buffer {
    method recommended-size(--> size_t) { ... }

    multi method new(Int $bufsize = self.recommended-size) {
        #self.new(nativecast(Pointer[uint8], CArray[uint8].allocate($bufsize)));
        self.new(CArray[uint8].allocate($bufsize + 1));
    }
    multi method new(CArray[uint8] $buffer) {
        my $result = self.bless(
            size => $buffer.elems - 1,
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
}

class Zstd::OutBuffer does Zstd::Buffer is repr<CStruct> is rw is export {
    has CArray[uint8] $.buffer;
    has size_t $.size;
    has size_t $.pos;

    submethod BUILD(:$!size, :$!pos) { }

    sub ZSTD_CStreamOutSize returns size_t is native('zstd') { }

    method recommended-size(--> size_t) { ZSTD_CStreamOutSize }
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

    method BUILD {
        $!cstream = Zstd::CStream.new;
        $!feedBuf = Zstd::InBuffer.new;
        $!resBuf  = Zstd::OutBuffer.new;

        $!feedBufSize = $!feedBuf.size;
        $!resBufSize = $!resBuf.size;

        $!compressorOutput .= new;
    }

    method !transport-output {
        if $!resBuf.pos > 0 {
            note " !!! resBuf position is not zero: $!resBuf.pos()";
            note "putting data into compressor output storage";
            $!compressorOutput.append($!resBuf.buffer[0 ..^ $!resBuf.pos].Array);
            $!resBuf.pos = 0;
            $!resBuf.size = $!resBufSize;

            # |---[=======]-------------|
            # ^ 0         ^ pos         ^ feedBufSize
            #     ^ prevPos
        }

    }

    method compress(buf8 $input) {
        note "want to compress $input.elems() bytes of data";
        if $input.elems {
            my $chunk = $input;
            my $output = buf8.new;
            while $chunk.elems() && $chunk.elems > $!feedBufSize {
               note "going for a partial chunk";
               my $partial = $chunk.splice(0, $!feedBufSize);
               say "chunk is now $chunk.elems() big, partial is $partial.elems()";
               if $partial.elems() {
                   my $res = self.compress($partial);
                   note "compressed! { $res.elems } bytes";
                   note "";
               }
               sleep 0.02;
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

            note "assigning $targetElems into the feed buffer";
            $target[$targetPos - 1] = $chunk[$targetPos - 1] while $targetPos++ < $targetElems;

            $!feedBuf.size = $targetElems;
            $!feedBuf.pos = 0;

            note "feeding input to compressor";
            note "next call ought to give { $!cstream.feed-input($!feedBuf, $!resBuf) } bytes";

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
        note "flushing stream";
        note $!cstream.flush-stream($!resBuf);

        self!transport-output;

        $!compressorOutput;
    }

    method end-stream {
        note "ending stream";
        note $!cstream.end-stream($!resBuf);

        self!transport-output;

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

    method BUILD {
        $!dstream = Zstd::DStream.new;
        $!feedBuf = Zstd::InBuffer.new;
        $!resBuf  = Zstd::OutBuffer.new;

        $!feedBufSize = $!feedBuf.size;
        $!resBufSize = $!resBuf.size;

        $!decompressorOutput .= new;
        $!leftOvers .= new;
    }

    method decompress(buf8 $input) {
        note "want to decompress $input.elems() bytes of data";
        if $input.elems > 0 {
            my $chunk = $input;
            my $output = buf8.new;
            while $chunk.elems() && $chunk.elems > $!feedBufSize {
               note "going for a partial chunk";
               my $partial = $chunk.splice(0, $!feedBufSize);
               say "chunk is now $chunk.elems() big";
               if $partial.elems() {
                   my $res = self.decompress($partial);
                   note "decompressed! { $res.elems } bytes";
                   note "";
               }
               sleep 0.02;
            }

            my int $targetPos = 0;
            my int $targetElems = $input.elems;

            my CArray[uint8] $target := $!feedBuf.buffer;

            note "assigning $targetElems into the feed buffer";
            $target[$targetPos - 1] = $chunk[$targetPos - 1] while $targetPos++ < $targetElems;

            $!feedBuf.size = $targetElems;
            $!feedBuf.pos = 0;

            note "feeding input to decompressor";
            my $nextfeed = $!dstream.feed-input($!feedBuf, $!resBuf);

            note "next feed should give $nextfeed bytes";

            if $!feedBuf.pos == $!feedBuf.size {
                $!feedBuf.pos = 0;
                $!feedBuf.size = 0;
            }
            else {
                note "left-overs?";
                if $nextfeed == 0 {
                    $!leftOvers.append($!feedBuf.buffer[$!feedBuf.pos ..^ $input.elems].Array);
                }
                else {
                    die "feeding more input when output buffer was full NYI";
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
        if $!resBuf.pos > 0 {
            note " !!! resBuf position is not zero: $!resBuf.pos()";
            note "putting data into compressor output storage";
            say $!resBuf.buffer[0..($!resBuf.pos)].Array.perl;
            $!decompressorOutput.append($!resBuf.buffer[0..($!resBuf.pos)].Array);
            $!resBuf.pos = 0;
            $!resBuf.size = $!resBufSize;

            # |---[=======]-------------|
            # ^ 0         ^ pos         ^ feedBufSize
            #     ^ prevPos
        }
    }
}

=begin pod

=head1 NAME

Compress::Zstd - blah blah blah

=head1 SYNOPSIS

=begin code :lang<perl6>

use Compress::Zstd;

=end code

=head1 DESCRIPTION

Compress::Zstd is ...

=head1 AUTHOR

Timo Paulssen <timonator@perpetuum-immobile.de>

=head1 COPYRIGHT AND LICENSE

Copyright 2019 Timo Paulssen

This library is free software; you can redistribute it and/or modify it under the Artistic License 2.0.

=end pod
