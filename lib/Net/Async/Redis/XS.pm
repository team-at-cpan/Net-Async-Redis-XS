package Net::Async::Redis::XS;
# ABSTRACT: faster

use strict;
use warnings;

our $VERSION = '0.001';

use parent qw(Net::Async::Redis);

package Net::Async::Redis::Protocol::XS {
    use parent qw(Net::Async::Redis::Protocol);

    sub decode {
        my ($self, $bytes) = @_;
        warn "decode buffer, size " . (length($$bytes)) . "\n";
        my @data = Net::Async::Redis::XS::decode_buffer($$bytes);
        warn "decoded buffer, size now " . (length($$bytes)) . "\n";
        $self->item($_) for @data;
    }
}

sub dl_load_flags { 1 }

require DynaLoader;
__PACKAGE__->DynaLoader::bootstrap(__PACKAGE__->VERSION);

sub wire_protocol {
    my ($self) = @_;
    $self->{wire_protocol} ||= do {
        Net::Async::Redis::Protocol::XS->new(
            handler  => $self->curry::weak::on_message,
            pubsub   => $self->curry::weak::handle_pubsub_message,
            error    => $self->curry::weak::on_error_message,
            protocol => $self->{protocol_level} || 'resp3',
        )
    };
}

1;

