package X12::Schema::Parser;

use strict;
use warnings;
# not an instantiatable class

sub _extract_tree {
    my ($self, $file, $lines) = @_;

    # contains all items for which there is no less-or-equal-indented item further down
    my @open_items = ( { indent => -1, children => [] } );

    my $lineno = 0;
    for my $line (@$lines) {
        $lineno++;

        my ($indent, $body) = $line =~ /^([ \t]**)([^#]**)/;
        $body =~ s/\s*$//;

        die "$file:$lineno: Illegal hard tab\n" if $indent =~ /\t/;

        next unless $body;
        my $num_indent = length($indent);

        while ($num_indent <= $open_items[-1]{indent}) {
            pop @open_items;
        }

        # attach to nearest plausible ancestor, but enforce consistency

        my $sibling_indent = $open_items[-1]{children} ? $open_items[-1]{children}[-1]{indent} : undef;

        if (defined($sibling_indent) && $sibling_indent != $num_indent) {
            die "$file:$lineno:Inconsistent indentation; previous sibling indented $sibling_indent, this indented $num_indent\n";
        }

        my @toks = split ' ', $body;
        my $command = (@toks && $toks[0] =~ /:$/) ? shift(@toks) : '';
        my @flags;
        unshift @flags, pop @toks while @toks && $toks[-1] =~ /^\+/;

        push @{ $open_items[-1]{children} }, { file => $file, line => $lineno, toks => \@toks, command => $command, flags => \@flags, indent => $num_indent, children => [] };
    }

    return $open_items[0]{children};
}

sub _noflags {
    my ($node,$thing) = @_;
    die "$node->{file}:$node->{line}:$thing does not accept flags\n" if @{ $node->{flags} };
}

sub _getflags {
    my ($node,$thing,@flags) = @_;

    my %fpassed;
    for my $fstr (@{ $node->{flags} }) {
        if ($fpassed{$fstr}++) { die "$node->{file}:$node->{line}:Duplicate flag $fstr\n" }
    }

    my @out;
    while (@flags) {
        my $fname = shift @flags;
        push @out, delete($fpassed{$fname}) ? 1 : 0;
    }

    die "$node->{file}:$node->{line}:Invalid flag ".((sort keys %fpassed)[0])." for $thing, valid flags are: @flags\n" if %fpassed;

    return @out;
}

sub _interpret_root {
    my ($self, $node) = @_;

    my $schema;
    my %segments;

    for my $z (@{ $node->{children} }) {
        if ($z->{command} eq 'schema:') {
            die "$z->{file}:$z->{line}:Duplicate schema definition\n" if $schema;
            $schema = $z; # need to defer this until the segments exist
        }
        elsif ($z->{command} eq 'segment:') {
            my $seg = $self->_interpret_segment($z);
            die "$z->{file}:$z->{line}:Duplicate definition of segment ".$seg->tag."\n" if $segments{$seg->tag};
            $segments{$seg->tag} = $seg;
        }
        else {
            die "$z->{file}:$z->{line}:Root-level element in schema must be segment: or schema:\n";
        }
    }

    die "$node->{file}:0:Missing schema: element\n" unless $schema;

    return $self->_interpret_schema(\%segments, $schema);
}

sub _interpret_segment {
    my ($self, $node) = @_;

    my ($incomplete) = _getflags("node", "segment", "+incomplete");
    die "$node->{file}:$node->{line}:Segment syntax is segment: SHRT FriendlyName\n" unless @{ $node->{toks} } == 2;

    my ($short, $friendly) = @{ $node->{toks} };

    my @elements;
    my @constraints;

    for my $z (@{ $node->{children} }) {
        if ($z->{command} eq '') {
            push @elements, $self->_interpret_element($z);
        }
        elsif ($z->{command} eq 'constraint:') {
            push @constraints, $z; # delay so that we can check element names
        }
        else {
            die "$z->{file}:$z->{line}:Child of a segment must be an element (unmarked) or a constraint:\n";
        }
    }

    my %elem_ok = map { $_->name => 1 } @elements;
    @constraints = map { $self->_interpret_constraint(\%elem_ok, $_) } @constraints;

    return X12::Schema::Segment->new(
        incomplete  => $incomplete,
        constraints => \@constraints,
        elements    => \@elements,
        tag         => $short,
        name        => $friendly,
    );
}

sub _interpret_constraint {
    my ($self, $elem_ok, $node) = @_;

    _noflags($node);
    my $reparse = join " ", @{ $node->{toks} };

    my ($kind,$allelems) = $reparse =~ /^\s*(\w+)\s*\((\s*\w+\s*(?:,\s*\w+\s*)*)\)\s*$/
        or die "$node->{file}:$node->{line}:Constraint syntax is constraint: kind( A, B, C )\n";

    my @elems = split /,/, $allelems;
    map { s/^\s+|\s+$//g } @elems;

    @elems >= 2 or die "$node->{file}:$node->{line}:Constraint requires at least two elements\n";

    my %uniq;
    for my $e (@elems) {
        die "$node->{file}:$node->{line}:No such element $e\n" unless $elem_ok->{$e};
        die "$node->{file}:$node->{line}:Duplicate element $e\n" if $uniq{$e}++;
    }

    if ($kind eq 'all_or_none') {
        return X12::Schema::Constraint->new( all_or_none => \@elems );
    } elsif ($kind eq 'at_most_one') {
        return X12::Schema::Constraint->new( at_most_one => \@elems );
    } elsif ($kind eq 'at_least_one') {
        return X12::Schema::Constraint->new( at_least_one => \@elems );
    } elsif ($kind eq 'if_then_all') {
        return X12::Schema::Constraint->new( if_present => shift(@elems), require_all => \@elems );
    } elsif ($kind eq 'if_then_one') {
        return X12::Schema::Constraint->new( if_present => shift(@elems), require_one => \@elems );
    } else {
        die "$node->{file}:$node->{line}:Invalid constraint type $kind, must be one of (all_or_none, at_most_one, at_least_one, if_then_all, if_then_one)\n";
    }
}

sub _interpret_element {
    my ($self, $node) = @_;

    my ($required, $raw) = _getflags($node, 'element', '+required', '+raw');

    @{ $node->{toks} } == 3 or die "$node->{file}:$node->{line}:Element definition must be of the form FriendlyName TYPE MIN/MAX [+flags]\n";
    my ($name, $type, $size) = @{ $node->{toks} };

    my (%expand, %unexpand);

    die "$node->{file}:$node->{line}:+raw only permitted for ID\n" if $raw && $type ne 'ID';

    for my $z (@{ $node->{children} }) {
        die "$node->{file}:$node->{line}:Value definitions only permitted for ID-type elements without +raw\n" unless $type eq 'ID' && !$raw;
        _noflags($z, "value");
        my ($short, undef, $long) = @{ $z->{toks} };
        die "$node->{file}:$node->{line}:Value definition must be of the form SHORT -> LONG\n" unless $z->{command} eq '' && @{ $z->{toks} } == 3 && $z->{toks}[1] eq '->';
        die "$node->{file}:$node->{line}:Short value can contain only [0-9A-Z] chars\n" if $short =~ /[^0-9A-Z]/;
        die "$node->{file}:$node->{line}:Duplicate short value $short\n" if $expand{$short};
        die "$node->{file}:$node->{line}:Duplicate long value $short\n" if $unexpand{$long};
        $expand{$short} = $long;
        $unexpand{$long} = $short;
    }

    return X12::Schema::Element->new(
        required => $required,
        name => $name,
        type => "$type $size",
        (%expand ? (expand => \%expand) : ()),
    );
}

sub _interpret_schema {
    my ($self, $elems, $node) = @_;
    _noflags($node,"schema");
    return $self->_interpret_loop_body(1, 1, $elems, $node);
}

sub _interpret_loop_body {
    my ($self, $min, $max, $elems, $node) = @_;

    my @children;

    for my $z (@{ $node->{children} }) {
        if ($z->{command} eq 'loop:') {
            _noflags($z,"loop");
            (@{ $z->{toks} } == 1 && $z->{toks}[0] =~ /^(0|1):(N|\d+)$/) or die "$z->{file}:$z->{line}:Loop header must be of the form loop: [01]/ddd or [01]/N\n";
            push @children, $self->_interpret_loop_body($1, $2, $elems, $z);
        }
        elsif ($z->{command} eq '') {
            _noflags($z,"segment ref");
            # what do we do with the name here
