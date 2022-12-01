# NAME

Net::Async::Redis::XS - like [Net::Async::Redis](https://metacpan.org/pod/Net%3A%3AAsync%3A%3ARedis) but faster

# SYNOPSIS

    use feature qw(say);
    use Future::AsyncAwait;
    use IO::Async::Loop;
    use Net::Async::Redis::XS;
    my $loop = IO::Async::Loop->new;
    $loop->add(my $redis = Net::Async::Redis::XS);
    await $redis->connect;
    await $redis->set('some-key', 'some-value');
    say await $redis->get('some-key');

# DESCRIPTION

This is a wrapper around [Net::Async::Redis](https://metacpan.org/pod/Net%3A%3AAsync%3A%3ARedis) with faster protocol parsing.

It implements the [Net::Async::Redis::Protocol](https://metacpan.org/pod/Net%3A%3AAsync%3A%3ARedis%3A%3AProtocol) protocol code in XS for better performance,
and will eventually be extended to optimise some other slow paths as well in future.

API and behaviour should be identical to [Net::Async::Redis](https://metacpan.org/pod/Net%3A%3AAsync%3A%3ARedis), see there for instructions.

# AUTHOR

Tom Molesworth <TEAM@cpan.org>

# LICENSE

Copyright Tom Molesworth 2022. Licensed under the same terms as Perl itself.
