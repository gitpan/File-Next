package File::Next;

use strict;
use warnings;

=head1 NAME

File::Next - File-finding iterator

=head1 VERSION

Version 1.00

=cut

our $VERSION = '1.00_01';

=head1 SYNOPSIS

File::Next is a lightweight, taint-safe file-finding module.
It's lightweight and has no non-core prerequisites.

    use File::Next;

    my $files = File::Next::files( '/tmp' );

    while ( defined ( my $file = $files->() ) ) {
        # do something...
    }

=head1 OPERATIONAL THEORY

The two major functions, I<files()> and I<dirs()>, return an iterator
that will walk through a directory tree.  The simplest use case is:

    use File::Next;

    my $iter = File::Next::files( '/tmp' );

    while ( defined ( my $file = $iter->() ) ) {
        print $file, "\n";
    }

    # Prints...
    /tmp/foo.txt
    /tmp/bar.pl
    /tmp/baz/1
    /tmp/baz/2.txt
    /tmp/baz/wango/tango/purple.txt

Note that only files are returned by C<files()>'s iterator.
Directories are ignored.

In list context, the iterator returns a list containing I<$dir>,
I<$file> and I<$fullpath>, where I<$fullpath> is what would get
returned in scalar context.

The first parameter to any of the iterator factory functions may
be a hashref of options.

=head1 ITERATORS

For the three iterators, the \%options are optional.

=head2 files( [ \%options, ] @starting_points )

Returns an iterator that walks directories starting with the items
in I<@starting_points>.  Each call to the iterator returns another
regular file.

=head2 dirs( [ \%options, ] @starting_points )

Returns an iterator that walks directories starting with the items
in I<@starting_points>.  Each call to the iterator returns another
directory.

=head2 everything( [ \%options, ] @starting_points )

Returns an iterator that walks directories starting with the items
in I<@starting_points>.  Each call to the iterator returns another
file, whether it's a regular file, directory, symlink, socket, or
whatever.

=head1 SUPPORT FUNCTIONS

=head2 sort_standard( $a, $b )

A sort function for passing as a C<sort_files> option:

    my $iter = File::Next::files( {
        sort_files => \&File::Next::sort_standard,
    }, 't/swamp' );

This function is the default, so the code above is identical to:

    my $iter = File::Next::files( {
        sort_files => 1,
    }, 't/swamp' );

=head2 sort_reverse( $a, $b )

Same as C<sort_standard>, but in reverse.

=head2 reslash( $path )

Takes a path with all forward slashes and rebuilds it with whatever
is appropriate for the platform.  For example 'foo/bar/bat' will
become 'foo\bar\bat' on Windows.

This is really just a convenience function.  I'd make it private,
but F<ack> wants it, too.

=cut

=head1 CONSTRUCTOR PARAMETERS

=head2 file_filter -> \&file_filter

The file_filter lets you check to see if it's really a file you
want to get back.  If the file_filter returns a true value, the
file will be returned; if false, it will be skipped.

The file_filter function takes no arguments but rather does its work through
a collection of variables.

=over 4

=item * C<$_> is the current filename within that directory

=item * C<$File::Next::dir> is the current directory name

=item * C<$File::Next::name> is the complete pathname to the file

=back

These are analogous to the same variables in L<File::Find>.

    my $iter = File::Next::files( { file_filter => sub { /\.txt$/ } }, '/tmp' );

By default, the I<file_filter> is C<sub {1}>, or "all files".

This filter has no effect if your iterator is only returning directories.

=head2 descend_filter => \&descend_filter

The descend_filter lets you check to see if the iterator should
descend into a given directory.  Maybe you want to skip F<CVS> and
F<.svn> directories.

    my $descend_filter = sub { $_ ne "CVS" && $_ ne ".svn" }

The descend_filter function takes no arguments but rather does its work through
a collection of variables.

=over 4

=item * C<$_> is the current filename of the directory

=item * C<$File::Next::dir> is the complete directory name

=back

The descend filter is NOT applied to any directory names specified
in as I<@starting_points> in the constructor.  For example,

    my $iter = File::Next::files( { descend_filter => sub{0} }, '/tmp' );

always descends into I</tmp>, as you would expect.

By default, the I<descend_filter> is C<sub {1}>, or "always descend".

=head2 error_handler => \&error_handler

If I<error_handler> is set, then any errors will be sent through
it.  By default, this value is C<CORE::die>.

=head2 sort_files => [ 0 | 1 | \&sort_sub]

If you want files sorted, pass in some true value, as in
C<< sort_files => 1 >>.

If you want a special sort order, pass in a sort function like
C<< sort_files => sub { $a->[1] cmp $b->[1] } >>.
Note that the parms passed in to the sub are arrayrefs, where $a->[0]
is the directory name, $a->[1] is the file name and $a->[2] is the
full path.  Typically you're going to be sorting on $a->[2].

=head2 follow_symlinks => [ 0 | 1 ]

If set to false, the iterator will ignore any files and directories
that are actually symlinks.  This has no effect on non-Unixy systems
such as Windows.  By default, this is true.

Note that this filter does not apply to any of the I<@starting_points>
passed in to the constructor.

=cut

use File::Spec       ();
use Archive::Extract ();
use File::Temp       ();
use ReleaseAction    ();
use File::Path       ();
use Carp::Clan;
use Storable ();

## no critic (ProhibitPackageVars)
our $name;    # name of the current file
our $dir;     # dir of the current file

our %files_defaults;
our %skip_dirs;

BEGIN {
    %files_defaults = (
        file_filter     => undef,
        descend_filter  => undef,
        error_handler   => \&confess,
        sort_files      => undef,
        follow_symlinks => 1,
    );
    %skip_dirs = map { ( $_, 1 ) } ( File::Spec->curdir, File::Spec->updir );
}

sub files {
    my ( $parms, @queue ) = _setup( \%files_defaults, @_ );
    my $filter = $parms->{file_filter};

    return sub {
        while (@queue) {
            my ( $dir, $file, $fullpath, $outside ) = splice( @queue, 0, 4 );
            if ( my $new_archive = _try_archive($fullpath) ) {
                unshift @queue,
                    _candidate_files(
                    {   archive  => $new_archive,
                        parms    => $parms,
                        fullpath => $fullpath,
                        ( outside => $outside ) x !!($outside),
                    }
                    );
            }
            elsif ( -f $fullpath ) {
                if ($filter) {
                    local $_                = $file;
                    local $File::Next::dir  = $dir;
                    local $File::Next::name = $fullpath;
                    next if not $filter->();
                }
                if ( not wantarray ) {
                    return $fullpath;
                }
                else {
                    my $archive_path = _archive_path( $dir, $file, $outside );
                    return ( $dir, $file, $fullpath, $archive_path );
                }
            }
            elsif ( -d _ ) {
                unshift @queue,
                    _candidate_files(
                    {   parms    => $parms,
                        fullpath => $fullpath,
                        ( outside => $outside ) x !!($outside),
                    }
                    );
            }
        }    # while

        return;
    };    # iterator
}

sub dirs {
    my ( $parms, @queue ) = _setup( \%files_defaults, @_ );

    return sub {
        while (@queue) {
            my ( undef, undef, $fullpath, $outside ) = splice( @queue, 0, 4 );
            if ( my $new_archive = _try_archive($fullpath) ) {
                unshift @queue,
                    _candidate_files(
                    {   archive  => $new_archive,
                        parms    => $parms,
                        fullpath => $fullpath,
                        ( outside => $outside ) x !!($outside),
                    }
                    );
                if ( not wantarray ) {
                    return $fullpath;
                }
                else {
                    my $archive_path
                        = _archive_path( $fullpath, undef, $outside );
                    return ( undef, undef, $fullpath, $archive_path );
                }
            }
            elsif ( -d $fullpath ) {
                unshift @queue,
                    _candidate_files(
                    {   parms    => $parms,
                        fullpath => $fullpath,
                        ( outside => $outside ) x !!$outside,
                    }
                    );
                if ( not wantarray ) {
                    return $fullpath;
                }
                else {
                    my $archive_path
                        = _archive_path( $fullpath, undef, $outside );
                    return ( undef, undef, $fullpath, $archive_path );
                }
            }
        }    # while

        return;
    };    # iterator
}

sub everything {
    my ( $parms, @queue ) = _setup( \%files_defaults, @_ );
    my $filter = $parms->{file_filter};

    return sub {
        while (@queue) {
            my ( $dir, $file, $fullpath, $outside ) = splice( @queue, 0, 4 );
            if ( my $new_archive = _try_archive($fullpath) ) {
                unshift @queue,
                    _candidate_files(
                    {   archive  => $new_archive,
                        parms    => $parms,
                        fullpath => $fullpath,
                        ( outside => $outside ) x !!($outside)
                    }
                    );
            }
            elsif ( -d $fullpath ) {
                unshift @queue,
                    _candidate_files(
                    {   parms    => $parms,
                        fullpath => $fullpath,
                        ( outside => $outside ) x !!($outside),
                    }
                    );
            }

            if ($filter) {
                local $_                = $file;
                local $File::Next::dir  = $dir;
                local $File::Next::name = $fullpath;
                next if not $filter->();
            }
            if ( not wantarray ) {
                return $fullpath;
            }
            else {
                $DB::single = 1 if $file =~ /ccc/;
                my $archive_path = _archive_path( $dir, $file, $outside );
                return ( $dir, $file, $fullpath, $archive_path );
            }
        }    # while

        return;
    };    # iterator
}

sub sort_standard($$) { return $_[0]->[1] cmp $_[1]->[1] }; ## no critic (ProhibitSubroutinePrototypes)
sub sort_reverse($$) { return $_[1]->[1] cmp $_[0]->[1] }; ## no critic (ProhibitSubroutinePrototypes)

sub reslash {
    my $path = shift;

    my @parts = split( /\//, $path );

    return $path if @parts < 2;

    return File::Spec->catfile(@parts);
}

=head1 PRIVATE FUNCTIONS

=head2 _setup( $default_parms, @whatever_was_passed_to_files() )

Handles all the scut-work for setting up the parms passed in.

Returns a hashref of operational options, combined between
I<$passed_parms> and I<$defaults>, plus the queue.

The queue prep stuff takes the strings in I<@starting_points> and
puts them in the format that queue needs.

The C<@queue> that gets passed around is an array that has three
elements for each of the entries in the queue: $dir, $file and
$fullpath.  Items must be pushed and popped off the queue three at
a time (spliced, really).

=cut

sub _setup {
    my $defaults = shift;
    my $passed_parms
        = ref $_[0] eq 'HASH' ? { %{ +shift } } : {};    # copy parm hash

    my %passed_parms = %{$passed_parms};

    my $parms = {};
    for my $key ( keys %{$defaults} ) {
        $parms->{$key}
            = exists $passed_parms{$key}
            ? delete $passed_parms{$key}
            : $defaults->{$key};
    }

    # Any leftover keys are bogus
    for my $badkey ( keys %passed_parms ) {
        my $sub = ( caller(1) )[3];
        $parms->{error_handler}->("Invalid option passed to $sub(): $badkey");
    }

    # If it's not a code ref, assume standard sort
    if ( $parms->{sort_files} && ( ref( $parms->{sort_files} ) ne 'CODE' ) ) {
        $parms->{sort_files} = \&sort_standard;
    }
    my @queue;

    for (@_) {
        my $start = reslash($_);
        if ( -d $start ) {
            push @queue, ( $start, undef, $start, undef );
        }
        else {
            push @queue, ( undef, $start, $start, undef );
        }
    }

    return ( $parms, @queue );
}

=head2 _candidate_files( { fullpath => ..., parms => ..., [ archive => ... ], [ outside => ... ] } )

Pulls out the files/dirs that might be worth looking into in I<fullpath>.
If I<fullpath> is the empty string, then search the current directory.

I<parms> is the hashref of parms passed into File::Next constructor.

I<archive> is an optional Archive::Extract object. If it is present,
it will be extracted to a temporary directory. Searching for files
resumes inside the temporary directory.

I<outside> is an optional parameter, used for garbage collection of
extracted on-disk archive contents, and when constructing a "logical"
filepath for files inside archives.

=cut

sub _candidate_files {
    my ($p) = @_;

    # Unpack the archive and retry from inside the archive.
    if ( exists $p->{archive} ) {
        return _candidate_files_from_archive($p);
    }
    else {
        return _candidate_files_from_directory($p);
    }
}

=head2 _candidate_files_from_archive( { fullpath => ..., parms => ..., archive => ..., [ outside => ... ] } )

Is used by I<_candidate_files>. See I<_candidate_files> for
information on the other parameters.

I<archive> is a mandatory Archive::Extract object.

=cut

sub _candidate_files_from_archive {

    # Make a copy of input but not the two objects.
    my ($p) = @_;

    # The real path is now inside this temp directory but preserve the
    # original path for later reconstruction. Also save the tmp root
    # so it can be removed from the fake path.
    my $tmpdir    = File::Temp::tempdir( CLEANUP => 1 );
    my $tmpdir_rx = qr/\A\Q$tmpdir\E/;
    my $cleanup   = ReleaseAction->new(
        sub {

            # print "DELETING $tmpdir\n";
            File::Path::rmtree($tmpdir);
        }
    );
    my %new_p = (

        # outside contains the archive path
        outside   => $p,
        tmpdir_rx => $tmpdir_rx,
        cleanup   => $cleanup,

        # The fake, on-disk path. Don
        fullpath => $tmpdir,
        parms    => $p->{parms},
    );

    # Woo! Extract the archive to disk and now just treat it like a
    # directory.
    # print "EXTRACTING $new_p{outside}{fullpath} to $tmpdir\n";
    $p->{archive}->extract( to => $tmpdir );

    # recurse.
    return _candidate_files_from_directory( \%new_p );
}

=head2 _candidate_files_from_directory( { fullpath => ..., parms => ..., [ outside => ... ] } )

Is used by I<_candidate_files>. See I<_candidate_files> for
information on the other parameters.

The I<archive> parameter must not be present.

=cut

sub _candidate_files_from_directory {
    my ($p) = @_;

    # Search this directory.
    my $dh;
    if ( !opendir $dh, $p->{fullpath} ) {
        $p->{parms}{error_handler}->("$p->{fullpath}: $!");
        return;
    }

    my @newfiles;
    while ( defined( my $file = readdir $dh ) ) {
        next if $skip_dirs{$file};

        # Only do directory checking if we have a descend_filter
        my $fullpath = File::Spec->catdir( $p->{fullpath}, $file );
        if ( !$p->{parms}{follow_symlinks} ) {
            next if -l $fullpath;
        }

        if ( $p->{parms}{descend_filter} && -d $fullpath ) {
            local $File::Next::dir = $fullpath;
            local $_               = $file;

            # JBJ: exception handling???
            next if not $p->{parms}{descend_filter}->();
        }
        push @newfiles, $p->{fullpath}, $file, $fullpath, $p;
    }
    closedir $dh;

    # Assert!
    @newfiles % 4 == 0
        or die;

    if ( my $sub = $p->{parms}{sort_files} ) {
        my @quads;
        while (@newfiles) {
            push @quads, [ splice( @newfiles, 0, 4 ) ];
        }
        @newfiles = map { @{$_} } sort $sub @quads;
    }

    # Assert!
    @newfiles % 4 == 0
        or die;

    return @newfiles;
}

=head2 _try_archive( $file )

Attempts to read I<$file> as an archive. Returns undef if it is not an
archive.

=cut

sub _NOTHING { }

sub _try_archive {
    my ($fullpath) = @_;
    local $@;
    local $Archive::Extract::WARN = 0;
    local $SIG{__WARN__}          = \&_NOTHING;
    local $SIG{__DIE__}           = \&_NOTHING;

    # print "TRYING $fullpath\n";
    my $archive = scalar
        eval { return Archive::Extract->new( archive => $fullpath ); };
    if ( defined $archive ) {

        # print "ARCHIVE: $fullpath\n";
    }
    return $archive;
}

=head2 _archive_path( $dir, $file, $archive )

Given a I<$dir>, I<$file>, and an optional originating I<$archive>,
return a meaningful file path. These paths are not necessarilly "real"
and cannot always be found directly on disk. They are "logical" in the
sense that things contained within archive files are treated as if the
archive were a directory. It makes for something readable to people or
software that expects it.

=cut

sub _archive_path {
    my ( $dir, $file, $archive ) = @_;
    if ( defined $archive ) {
        if ( defined $archive->{tmpdir_rx} ) {
            $dir =~ s/$archive->{tmpdir_rx}/$archive->{outside}{fullpath}/
                or warn;
        }
        return _archive_path( $dir, $file, $archive->{outside} );
    }
    elsif ( defined $dir and defined $file ) {
        return File::Spec->catfile( $dir, $file );
    }
    elsif ( defined $dir ) {
        return $dir;
    }
    else {
        return $file;
    }
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

=item * Subversion repository

L<https://file-next.googlecode.com/svn/trunk>

=back

=head1 ACKNOWLEDGEMENTS

All file-finding in this module is adapted from Mark Jason Dominus'
marvelous I<Higher Order Perl>, page 126.

=head1 COPYRIGHT & LICENSE

Copyright 2006-2007 Andy Lester, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

1;    # End of File::Next
