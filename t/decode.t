use strict;
use warnings;

use Test::More;
use Test::Fatal;
use Net::Async::Redis::XS;

my $instance = Net::Async::Redis::Protocol::XS->new;

++$|;
like(exception {
    Net::Async::Redis::XS::decode_buffer($instance, [])
}, qr/expected a string/, 'complains about bad types');
like(exception {
    Net::Async::Redis::XS::decode_buffer($instance, {})
}, qr/expected a string/, 'complains about bad types');

our $Z = "\x0D\x0A";
is(Net::Async::Redis::XS::decode_buffer($instance, ":3$Z"), 3, 'can decode_buffer');
is(Net::Async::Redis::XS::decode_buffer($instance, ":0$Z"), 0, 'can decode_buffer');
isnt(Net::Async::Redis::XS::decode_buffer($instance, ":23$Z"), 22, 'can decode_buffer');
is(Net::Async::Redis::XS::decode_buffer($instance, "+example$Z"), 'example', 'can decode_buffer');
is(Net::Async::Redis::XS::decode_buffer($instance, "-error$Z"), undef, 'can decode_buffer');
is_deeply(Net::Async::Redis::XS::decode_buffer($instance, "*1$Z+test$Z"), ['test'], 'can decode_buffer');
is_deeply(Net::Async::Redis::XS::decode_buffer($instance, "*1$Z*1$Z+test$Z"), [['test']], 'can decode_buffer');

is_deeply([ Net::Async::Redis::XS::decode_buffer($instance, ":18$Z") ], [ 18 ], 'integer should yield one item');
{
    my $err;
    local $instance->{error} = sub { fail('called more than once') if $err; $err = shift; };
    is_deeply([ Net::Async::Redis::XS::decode_buffer($instance, "-error$Z") ], [ ], 'error should yield no items');
    is($err, 'error');
}
is_deeply(
    Net::Async::Redis::XS::decode_buffer($instance, 
        "*1$Z*1$Z*2$Z:8$Z*6$Z+a$Z+1$Z+b$Z+2$Z+c$Z+3$Z"
    ), [
        [
            [
                8, [
                    'a', '1', 'b', '2', 'c', '3'
                ]
            ]
        ]   
    ],
    'can decode_buffer'
);

done_testing;

