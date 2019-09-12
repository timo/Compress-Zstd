use v6.c;
use Test;
use Compress::Zstd;

my Zstd::InBuffer $feedBuf .= new;
my Zstd::OutBuffer $resBuf .= new;

my buf8 $full-input .= new(flat("a".."z", "0".."9", "A".."Z", "☺", "a" xx 50).Bag.roll($feedBuf.size).join.encode("utf8"));
my buf8 $full-result.= new;

my $compressor = Zstd::CStream.new();

diag $feedBuf.size;
diag $resBuf.size;

for ^$feedBuf.size {
    $feedBuf.buffer[$_] = $full-input[$_];
}

diag "return value of feed-input for compressor: "~ $compressor.feed-input($feedBuf, $resBuf);

ok $feedBuf.pos != 0, "feed buffer's position has moved: $feedBuf.pos() $feedBuf.size()";
ok $resBuf.pos != 0, "result buffer's position has moved: $resBuf.pos() $resBuf.size()";

my $decompressor = Zstd::DStream.new();

my Zstd::InBuffer $decFeedBuf .= new($resBuf.size);
my Zstd::OutBuffer $decResBuf .= new($feedBuf.size);

for ^$resBuf.size {
    $decFeedBuf.buffer[$_] = $resBuf.buffer[$_];
}

$resBuf.pos = 0;

diag "return value of feed-input on decompressor: "~ $decompressor.feed-input($decFeedBuf, $decResBuf);

ok $decFeedBuf.pos != 0, "feed buffer's position has moved: $decFeedBuf.pos() $decFeedBuf.size()";
ok $decResBuf.pos != 0, "result buffer's position has moved: $decResBuf.pos() $decResBuf.size()";

diag "original string (first 100 chars)";
diag Buf.new($feedBuf.buffer[^$feedBuf.size]).decode("utf8").substr(0, 100);
diag "decompressed string (first 100 chars)";
diag Buf.new($decResBuf.buffer[^$decResBuf.size]).decode("utf8-c8").substr(0, 100);

diag "output from finish-stream: " ~ $compressor.end-stream($resBuf);

ok $feedBuf.pos != 0, "feed buffer's position has moved: $feedBuf.pos() $feedBuf.size()";
ok $resBuf.pos != 0, "result buffer's position has moved: $resBuf.pos()  $resBuf.size()";

diag "output from decoder: " ~ $decompressor.feed-input($decFeedBuf, $decResBuf);

done-testing;
