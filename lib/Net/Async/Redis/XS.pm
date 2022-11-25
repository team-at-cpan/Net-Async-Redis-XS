package Net::Async::Redis::XS;
# ABSTRACT: faster

use strict;
use warnings;

our $VERSION = '0.001';

sub dl_load_flags { 1 }

require DynaLoader;
__PACKAGE__->DynaLoader::bootstrap(__PACKAGE__->VERSION);

1;

