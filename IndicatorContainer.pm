package IndicatorContiner;

use strict;
use warnings;
use Exporter;

use vars qw(@ISA @EXPORT @EXPORT_OK %EXPORT_TAGS $VERSION);
$VERSION = 1.00;              # Or higher
@ISA = qw(Exporter);
@EXPORT = qw(new );

sub new {
    my $class = shift;
    my $self = bless {}, $class;
    return $self;
}


1;
