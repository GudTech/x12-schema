package X12::Schema::TokenSink;

use Moose;
use namespace::autoclean;

has delim_re => (is => 'ro', isa => 'RegexpRef', init_arg => undef);
has non_charset_re => (is => 'ro', isa => 'RegexpRef', default => sub { qr/(?!)/ });

has [qw( segment_term element_sep component_sep )] => (is => 'ro', isa => 'Str', required => 1);
has repeat_sep => (is => 'ro', isa => 'Str');

has output => (is => 'rw', isa => 'Str', default => '', init_arg => undef);
has output_func => (is => 'rw', isa => 'CodeRef');
has segment_counter => (is => 'rw', isa => 'Int', default => 0, init_arg => undef);

# DIVERSITY: this will need to include flags to control the output in other ways, such as UN/EDIFACT mode, whether to use exponential notation, etc

sub BUILD {
    my ($self) = @_;

    my %all_seps;
    $self->segment_term =~ /^.\r?\n?$/ or confess "segment_term must be a single character, optionally followed by CR and/or LF";
    $all_seps{substr($self->segment_term,0,1)}++;

    for (qw( element_sep repeat_sep component_sep )) {
        $self->$_ or next;
        length($self->$_) == 1 or confess "$_ must be a single character";
        $all_seps{$self->$_}++;
    }

    grep(($_ > 1), values %all_seps) and confess "all delimiters must be unique";
    my $re = '[' . quotemeta(join '', sort keys %all_seps) . ']';
    $self->{delim_re} = qr/$re/;
}

sub segment {
    my ($self, $seg) = @_;

    $self->{segment_counter}++;
    $self->{output_func} ? $self->{output_func}->($seg) : ( $self->{output} .= $seg );
}

__PACKAGE__->meta->make_immutable;
