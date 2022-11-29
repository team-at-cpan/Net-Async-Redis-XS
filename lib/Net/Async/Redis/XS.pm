package Net::Async::Redis::XS;
# ABSTRACT: faster

use strict;
use warnings;
use parent qw(Net::Async::Redis);

our $VERSION = '0.001';

sub dl_load_flags { 1 }

require DynaLoader;
__PACKAGE__->DynaLoader::bootstrap(__PACKAGE__->VERSION);

sub decode {
    my ($self, $bytes) = @_;
    my @data = decode_buffer($$bytes);
    $self->item($_) for @data;
}

1;

