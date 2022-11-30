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
note 'nested';
no_growth {
    my @x = Net::Async::Redis::XS::decode_buffer($instance, 
        "*1$Z*1$Z*2$Z:8$Z*6$Z+a$Z:83894$Z+b$Z+2$Z+c$Z+3$Z"
    );
} 'Constructing Some::Class does not grow memory';

done_testing;

