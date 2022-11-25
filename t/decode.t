use strict;
use warnings;

use Test::More;
use Test::Fatal;
use Net::Async::Redis::XS;

like(exception {
    Net::Async::Redis::XS::decode([])
}, qr/expected a string/, 'complains about bad types');
like(exception {
    Net::Async::Redis::XS::decode({})
}, qr/expected a string/, 'complains about bad types');

our $Z = "\x0D\x0A";
is(Net::Async::Redis::XS::decode(":3\x0D\x0A"), 3, 'can decode');

done_testing;

