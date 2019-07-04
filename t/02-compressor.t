use v6.c;
use Test;
use Compress::Zstd;

my $comp = Zstd::Compressor.new;

my $result = $comp.compress(my $input-buf = buf8.new(q:to/INPUT/.encode("utf8").list));
    hello there. how are you today? i am feeling quite fine indeed.
    i hope this compression stuff will work. how about you?
    INPUT


diag $result.elems;

$result = $comp.end-stream;

diag $result.list.fmt("%02x");

diag "after end-stream, result is $result.elems() bytes big";

my $decomp = Zstd::Decompressor.new;

$result.append(my $leftover-buf = "LEFTOVER1LEFTOVER2LEFTOVER3".encode("utf8"));

my $decresult = $decomp.decompress($result);
diag $decresult.decode("utf8");

is-deeply $decresult, $input-buf, "decompressed is eqv to input";

is-deeply $decomp.get-leftovers.list, $leftover-buf.list, "leftovers after zstd stream is kept around";

done-testing;