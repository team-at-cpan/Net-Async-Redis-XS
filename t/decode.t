use strict;
use warnings;

use Test::More;
use Test::Fatal;
use Net::Async::Redis::XS;

++$|;
like(exception {
    Net::Async::Redis::XS::decode([])
}, qr/expected a string/, 'complains about bad types');
like(exception {
    Net::Async::Redis::XS::decode({})
}, qr/expected a string/, 'complains about bad types');

our $Z = "\x0D\x0A";
is(Net::Async::Redis::XS::decode(":3$Z"), 3, 'can decode');
is(Net::Async::Redis::XS::decode(":0$Z"), 0, 'can decode');
isnt(Net::Async::Redis::XS::decode(":23$Z"), 22, 'can decode');
is(Net::Async::Redis::XS::decode("+example$Z"), 'example', 'can decode');
is_deeply(Net::Async::Redis::XS::decode("*1$Z+test$Z"), ['test'], 'can decode');
is_deeply(Net::Async::Redis::XS::decode("*1$Z*1$Z+test$Z"), [['test']], 'can decode');
is_deeply(
    Net::Async::Redis::XS::decode(
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
    'can decode'
);

done_testing;

