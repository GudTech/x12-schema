package X12::Schema;

use Moose;
use namespace::autoclean;
use File::Slurp qw( read_file );

has root => (is => 'ro', isa => 'X12::Schema::Sequence');
has type => (is => 'ro', isa => 'Str');
has name => (is => 'ro', isa => 'Str');
has alternates => (is => 'ro', isa => 'HashRef[X12::Schema]');
has ignore_component_sep => (is => 'ro', isa => 'Bool', default => 0);

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

sub _make_tokensource {
    my ($self, $text) = @_;
    require X12::Schema::TokenSource;
    X12::Schema::TokenSource->new( ignore_component_sep => $self->ignore_component_sep, buffer => $text );
}

sub parse {
    my ($self, $text) = @_;

    require X12::Schema::ControlSyntaxX12;

    my $src = $self->_make_tokensource($text);
    my $ctl = X12::Schema::ControlSyntaxX12->new( schema => $self );

    my $interchange = $ctl->parse_interchange( $src );
    $src->expect_eof;

    return $interchange;
}

sub parse_concatenation {
    my ($self, $text, %opts) = @_;

    require X12::Schema::ControlSyntaxX12;

    my $src = $self->_make_tokensource($text);
    my $ctl = X12::Schema::ControlSyntaxX12->new( schema => $self );

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
    my $ctl = X12::Schema::ControlSyntaxX12->new( schema => $self );

    $ctl->emit_interchange( $sink, $interchange );

    return $sink->output;
}

__PACKAGE__->meta->make_immutable;
