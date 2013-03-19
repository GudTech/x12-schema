package X12::Schema;

use Moose;
use namespace::autoclean;
use File::Slurp qw( read_file );

has root => (is => 'ro', isa => 'X12::Schema::Sequence', required => 1);

sub loadstring {
    my ($pkg, %args) = @_;

    require X12::Schema::Parser; # laziness, also avoid a circularity

    confess "text argument required" unless $args{text};
    return X12::Schema::Parser->parse( $args{filename} || 'ANON', $args{text} );
}

sub loadfile {
    my ($pkg, %args) = @_;

    return $pkg->loadstring( filename => $args{file}, text => scalar(read_file($args{file})) );
}

sub parse {
    my ($self, $text) = @_;

    require X12::Schema::TokenSource;
    require X12::Schema::ControlSyntaxX12;

    my $src = X12::Schema::TokenSource->new( buffer => $text );
    my $ctl = X12::Schema::ControlSyntaxX12->new( tx_set_def => $self->root );

    my $interchange = $ctl->parse_interchange( $src );
    $src->expect_eof;

    return $interchange;
}

__PACKAGE__->meta->make_immutable;
