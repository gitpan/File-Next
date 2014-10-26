package File::Next;

use strict;
use warnings;

=head1 NAME

File::Next - File-finding iterator

=head1 VERSION

Version 0.01

=cut

our $VERSION = '0.01';

=head1 SYNOPSIS

File::Next is a lightweight, taint-safe file-finding module.
It's lightweight and has no prerequisites.

    use File::Next;

    my $files = File::Next->files( '/tmp' );

    while ( my $file = $files->() ) {
        # do something...
    }

=head1 OPERATIONAL THEORY

Each of the public functions in File::Next returns an iterator that
will walk through a directory tree.  The simplest use case is:

    use File::Next;

    my $iter = File::Next->files( '/tmp' );

    while ( my $file = $iter->() ) {
        print $file, "\n";
    }

    # Prints...
    /tmp/foo.txt
    /tmp/bar.pl
    /tmp/baz/1
    /tmp/baz/2.txt
    /tmp/baz/wango/tango/purple.txt

Note that only files are returned by C<files()>'s iterator.

The first parameter to any of the iterator factory functions may be a hashref of parameters.

=head1 PARAMETERS

=head2 file_filter -> \&file_filter

The file_filter lets you check to see if it's really a file you
want to get back.  If the file_filter returns a true value, the
file will be returned; if false, it will be skipped.

The full path of the file, based on your starting point, is set in
C<$_>, not unlike L<File::Find>.

    my $iter = File::Find::files( { file_filter => sub { /\.txt$/ } }, '/tmp' );

By default, the I<file_filter> is C<sub {1}>, or "all files".

=head2 descend_filter => \&descend_filter

The descend_filter lets you check to see if the iterator should
descend into a given directory.  Maybe you want to skip F<CVS> and
F<.svn> directories.

    my $descend_filter = sub { $_ ne "CVS" && $_ ne ".svn" }

The descend filter is NOT applied to any directory names specified
in the constructor.  For example,

    my $iter = File::Find::files( { descend_filter => sub{0} }, '/tmp' );

always descends into I</tmp>, as you would expect.

By default, the I<descend_filter> is C<sub {1}>, or "always descend".

=head2 error_handler => \&error_handler

If I<error_handler> is set, then any errors will be sent through
it.  By default, this value is C<CORE::die>.

=head1 FUNCTIONS

=head2 files( { \%parameters }, @starting points )

Returns an iterator that walks directories starting with the items
in I<@starting_points>.

All file-finding in this module is adapted from Mark Jason Dominus'
marvelous I<Higher Order Perl>, page 126.

=cut

sub files {
    my $parms = ref $_[0] eq 'HASH' ? {%{+shift}} : {}; # copy parm hash
    $parms->{file_filter} ||= sub {1};
    $parms->{descend_filter} ||= sub {1};
    $parms->{error_handler} ||= \&CORE::die;

    my @start = @_;

    my @queue;

    for my $start ( @start ) {
        if (-d $start) {
            push @queue, _candidate_files( {descend_filter=>sub{1}, file_filter=>$parms->{file_filter}}, $start );
        }
        else {
            push @queue, $start;
        }
    }

    return sub {
        while (@queue) {
            my $file = shift @queue;

            if (-d $file) {
                push( @queue, _candidate_files( $parms, $file ) );
            }
            elsif (-f $file) {
                local $_ = $file;
                return $file if $parms->{file_filter}->();
            }
        } # while
        return;
    }; # iterator
}

=for private _candidate_files( $parms, $dir )

Pulls out the files/dirs that might be worth looking into in I<$dir>.
If I<$dir> is the empty string, then search the current directory.
This is different than explicitly passing in a ".", because that
will get prepended to the path names.

I<$parms> is the hashref of parms passed into File::Next constructor.

=cut

sub _candidate_files {
    my $parms = shift;
    my $dir = shift;

    return $dir unless -d $dir;

    my $dh;
    if ( !opendir $dh, $dir ) {
        $parms->{error_handler}->( "$dir: $!" );
        return;
    }

    my @newfiles;
    while ( my $file = readdir $dh ) {
        next if $file =~ /^\.{1,2}$/;
        local $_ = $file;
        push @newfiles, $file if $parms->{descend_filter}->();
    }
    @newfiles = map { "$dir/$_" } @newfiles;

    return @newfiles;
}


=head1 AUTHOR

Andy Lester, C<< <andy at petdance.com> >>

=head1 BUGS

Please report any bugs or feature requests to
C<bug-file-next at rt.cpan.org>, or through the web interface at
L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=File-Next>.
I will be notified, and then you'll automatically be notified of
progress on your bug as I make changes.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc File::Next

You can also look for information at:

=over 4

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/File-Next>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/File-Next>

=item * RT: CPAN's request tracker

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=File-Next>

=item * Search CPAN

L<http://search.cpan.org/dist/File-Next>

=back

=head1 ACKNOWLEDGEMENTS

=head1 COPYRIGHT & LICENSE

Copyright 2006 Andy Lester, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

1; # End of File::Next
