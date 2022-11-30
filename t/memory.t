use strict;
use warnings;

use Test::More;
use Test::MemoryGrowth;

use Test::Fatal;
use Net::Async::Redis::XS;

my $instance = Net::Async::Redis::Protocol::XS->new;
our $Z = "\x0D\x0A";
note 'scalar';
no_growth {
    my $ret = Net::Async::Redis::XS::decode_buffer($instance, ":3$Z");
    die unless $ret == 3;
} 'Constructing Some::Class does not grow memory';
note 'array';
no_growth {
    my ($ret) = Net::Async::Redis::XS::decode_buffer($instance, ":3$Z");
    die unless $ret == 3;
} 'Constructing Some::Class does not grow memory';

done_testing;

