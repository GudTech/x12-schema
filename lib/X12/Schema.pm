package X12::Schema;

use Moose;
use namespace::autoclean;
use File::Slurp qw( read_file );

has root => (is => 'ro', isa => 'X12::Schema::Sequence', required => 1);

sub parse {
    my ($pkg, %args) = @_;

    require X12::Schema::Parser; # laziness, also avoid a circularity

    confess "text argument required" unless $args{text};
    return X12::Schema::Parser->parse( $args{filename} || 'ANON', $args{text} );
}

sub parsefile {
    my ($pkg, %args) = @_;

    return $pkg->parse( filename => $args{file}, text => scalar(read_file($args{file})) );
}

__PACKAGE__->meta->make_immutable;
