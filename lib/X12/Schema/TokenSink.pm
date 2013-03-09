package X12::Schema::TokenSink;

use Moose;
use namespace::autoclean;

has delim_re => (is => 'ro', isa => 'RegexpRef', init_arg => undef);

has [qw( segment_term element_sep repeat_sep component_sep )] => (is => 'ro', isa => 'Str', required => 1);

has output => (is => 'ro', isa => 'Str', default => '', init_arg => undef);
has output_func => (is => 'ro', isa => 'CodeRef');

# DIVERSITY: this will need to include flags to control the output in other ways, such as UN/EDIFACT mode, whether to use exponential notation, etc

sub BUILD {
    my ($self) = @_;

    my %all_seps;
    $self->segment_term =~ /^.\r?\n?$/ or confess "segment_term must be a single character, optionally followed by CR and/or LF";
    $all_seps{substr($self->segment_term,0,1)} = 1;

    for (qw( element_sep repeat_sep component_sep )) {
        length($self->$_) == 1 or confess "$_ must be a single character";
        $all_seps{$self->$_} = 1;
    }

    keys(%all_seps) == 4 or confess "all delimiters must be unique";
    my $re = '[' . quotemeta(join '', sort keys %all_seps) . ']';
    $self->{delim_re} = qr/$re/;
}

sub segment {
    my ($self, $seg) = @_;

    $self->{output_func} ? $self->{output_func}->($seg) : ( $self->{output} .= $seg );
}

__PACKAGE__->meta->make_immutable;
