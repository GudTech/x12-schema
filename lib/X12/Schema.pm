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

sub parse_concatenation {
    my ($self, $text) = @_;

    require X12::Schema::TokenSource;
    require X12::Schema::ControlSyntaxX12;

    my $src = X12::Schema::TokenSource->new( buffer => $text );
    my $ctl = X12::Schema::ControlSyntaxX12->new( tx_set_def => $self->root );

    my @list;
    while ($src->peek) {
        push @list, $ctl->parse_interchange( $src );
    }
    $src->expect_eof;

    return wantarray ? @list : \@list;
}

sub emit {
    my ($self, $sink_params, $interchange) = @_;

    require X12::Schema::TokenSink;
    require X12::Schema::ControlSyntaxX12;

    my $sink = X12::Schema::TokenSink->new( %$sink_params );
    my $ctl = X12::Schema::ControlSyntaxX12->new( tx_set_def => $self->root );

    $ctl->emit_interchange( $sink, $interchange );

    return $sink->output;
}

__PACKAGE__->meta->make_immutable;
