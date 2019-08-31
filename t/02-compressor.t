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

sub compress-decompress-test($input is rw) {
    my $comp = Zstd::Compressor.new;
    $comp.compress($input.clone);
    my $result = $comp.end-stream;

    note "compress result of   $input.VAR.name() is $result.elems() bytes big";

    my $decomp = Zstd::Decompressor.new;
    my $decresult = $decomp.decompress($result);

    note "decompress result of $input.VAR.name() is $decresult.elems() bytes big";

    #"/tmp/decresult.txt".IO.spurt($decresult.join("\n"));
    #"/tmp/input.txt".IO.spurt($input.join("\n"));

    is-deeply $decresult, $input, $input.VAR.name;
}

my $big-input-randoms = buf8.new(^255 .roll(1024 * 1024));
compress-decompress-test($big-input-randoms);

my $really-big-input-randoms = buf8.new(^255 .roll(1024 * 1024 * 8));
compress-decompress-test($really-big-input-randoms);

my @input-words = buf8.new(^255 .roll(64)) xx 32;
my $big-input-sameys = buf8.new(flat @input-words.roll(1024 * 16)>>.Slip);
compress-decompress-test($big-input-sameys);

my $really-big-input-sameys = buf8.new(flat @input-words.roll(1024 * 128)>>.Slip);
compress-decompress-test($really-big-input-sameys);

done-testing;
