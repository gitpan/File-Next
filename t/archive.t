#!perl -T

use strict;
use warnings;
use Test::More tests => 3;

use lib 't';
use Util;
use File::Next;

{
    my $iter     = File::File::everything('t/swamp/ddd.tar.gz');
    my @actual   = slurp($iter);
    my @expected = qw(
        t/swamp/ddd.tar.gz
        t/swamp/ddd.tar.gz/ccc
        t/swamp/ddd.tar.gz/ccc/bbb.tar.gz
        t/swamp/ddd.tar.gz/ccc/bbb.tar.gz/aaa
        t/swamp/ddd.tar.gz/ccc/bbb.tar.gz/aaa/world.txt
    );
    sets_match( \@actual, \@expected, '...' );
}

{
    my $iter     = File::File::files('t/swamp/ddd.tar.gz');
    my @actual   = slurp($iter);
    my @expected = qw(
        t/swamp/ddd.tar.gz/ccc/bbb.tar.gz/aaa/world.txt
    );
    sets_match( \@actual, \@expected, '...' );
}

{
    my $iter     = File::File::dirs('t/swamp/ddd.tar.gz');
    my @actual   = slurp($iter);
    my @expected = qw(
        t/swamp/ddd.tar.gz
        t/swamp/ddd.tar.gz/ccc
        t/swamp/ddd.tar.gz/ccc/bbb.tar.gz
        t/swamp/ddd.tar.gz/ccc/bbb.tar.gz/aaa
    );
    sets_match( \@actual, \@expected, '...' );
}
