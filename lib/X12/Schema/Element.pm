package X12::Schema::Element;

use Moose;
use namespace::autoclean;

has name       => (is => 'ro', isa => 'Str', required => 1);
has required   => (is => 'ro', isa => 'Bool', default => 0);

has type       => (is => 'ro', isa => 'Str', required => 1);
has expand     => (is => 'ro', isa => 'HashRef[Str]');

has scale      => (is => 'ro', isa => 'Int', init_arg => undef);
has min_length => (is => 'ro', isa => 'Int', init_arg => undef);
has max_length => (is => 'ro', isa => 'Int', init_arg => undef);
has contract   => (is => 'ro', isa => 'HashRef[Str]', init_arg => undef);

sub BUILD {
    my ($self) = @_;

    $self->{type} =~ /^(N|AN|DT|TM|ID|R)(\d*) (\d+)\/(\d+)$/ or confess "type at BUILD must look like N5 10/20";

    confess "Numeric postfix used only with N" if ($1 eq 'N') != ($2 ne '');
    confess "expand required iff type = ID" if ($1 eq 'ID') != (defined $self->expand);

    confess "Unsupported date format $self->{type}" if ($1 eq 'DT') && (($3 != $4) || ($3 != 6 && $3 != 8));
    confess "Unsupported time format $self->{type}" if ($1 eq 'TM') && (($3 != $4) || ($3 != 6 && $3 != 8 && $3 != 4));

    $self->{type} = $1;
    $self->{scale} = $2 if $2;
    $self->{min_length} = $3;
    $self->{min_length} = $4;

    $self->{contract} = $self->expand && { reverse %{ $self->expand } };
}

sub encode {
    my ($self, $sink, $value) = @_;

    my $cookvalue;
    my $type = $self->{type};
    my $maxp = $self->{max_length};
    my $minp = $self->{min_length};

    # let's assume no-one is dumb enough to pick 0-9, +, -, . as seps
    # can't just use sprintf for these two because field widths are in _digits_.  sign magnitude hoy!
    if ($type eq 'R') {

        my $prec = $maxp - 1;
        my $string;

        # this is a lot more complicated than it might otherwise be because the # of digits to the left of the decimal might increase after rounding on the right...

        while ($prec >= 0) {
            $string = sprintf "%.*f", $prec, $value;
            ($string =~ tr/0-9//) <= $maxp and last;
            $prec--;
        }

        if ($prec < 0) {
            die "Value $value canot fit in $maxp digits for ".$self->name;
        }

        my $wid = 0;

        while (1) {
            $string = sprintf "%0*.*f", $wid, $prec, $value;
            ($string =~ tr/0-9//) >= $minp and last;
            $wid++;
        }

        return $string; # phew!
    }

    if ($type eq 'N') {
        my $munge = $value * (10 ** $self->{scale});
        my $string;
        my $wid = 0;

        while (1) {
            $string = sprintf "%0*d", $wid, $value;
            ($string =~ tr/0-9//) >= $minp and last;
            $wid++;
        }

        ($string =~ tr/0-9//) >= $maxp and die "Value $value cannot fit in $maxp digits for ".$self->name;
        return $string;
    }

    if ($type eq 'ID') {
        # munge to string
        # deliberate fall through
    }

    if ($type eq 'AN') {
    }

    if ($type eq 'DT') {
    }

    if ($type eq 'TM') {
    }
}

__PACKAGE__->meta->make_immutable;
