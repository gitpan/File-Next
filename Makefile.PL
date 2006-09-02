package main;
use strict;
use warnings;
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME                => 'File::Next',
    AUTHOR              => 'Andy Lester <andy@petdance.com>',
    VERSION_FROM        => 'Next.pm',
    ABSTRACT_FROM       => 'Next.pm',
    PL_FILES            => {},
    PREREQ_PM => {
        'Test::More' => 0,
        'File::Spec' => 0,
    },
    dist                => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
    clean               => { FILES => 'File-Next-*' },
);

sub MY::postamble {
return <<'MAKE_FRAG';
.PHONY: tags critic

critic:
	perlcritic -1 -quiet .

MAKE_FRAG
}

1;