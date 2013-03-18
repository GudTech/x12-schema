use strict;
use warnings;
use Test::More tests => 16;
use Test::Exception;

BEGIN { use_ok('X12::Schema::TokenSource') or die }

my $O;

my $ISA1 = 'ISA*00*          *00*          *ZZ*TEST           *ZZ*TEST           *010101*1200*U*00401*000001208*0*P*/~';
my $ISA2 = 'ISA*00*          *00*          *ZZ*TEST           *ZZ*TEST           *010101*1200*U*00402*000001208*0*P*/~';
my $ISA3 = 'ISA*00*          *00*          *ZZ*TEST           *ZZ*TEST           *010101*1200*~*00402*000001208*0*P*/~';

$O = new_ok 'X12::Schema::TokenSource', [ buffer => "${ISA1}FOO*BUR~" ], "create source with 2 tokens";

is ref($O->get), 'ARRAY', 'can read ISA';

is_deeply $O->peek, [ [['FOO']], [['BUR']] ], 'can peek next';
is_deeply $O->peek, [ [['FOO']], [['BUR']] ], 'can peek next twice';
is $O->peek_code, 'FOO', 'peek-code';
is_deeply $O->get, [ [['FOO']], [['BUR']] ], 'can get peeked value';

ok !defined($O->peek), 'peek on empty is undef';
ok !defined($O->get), 'get on empty is undef';
is_deeply $O->peek_code, '', 'peek_code on empty is ""';

is $O->segment_counter, 2, "segment_counter counts actually used segments";

lives_ok { $O->expect_eof } 'nothing trailing';


$O = X12::Schema::TokenSource->new(buffer => "${ISA2}\r\nFOO*BUR/S*A/B~\r\nK");

$O->get;

is_deeply $O->get, [ [['FOO']], [['B'],['R','S']], [['A','B']] ], "parsing test for 'advanced features'";

throws_ok { $O->expect_eof } qr/Unexpected/, 'trailing garbage noticed by expect_eof';

$O = X12::Schema::TokenSource->new(buffer => "${ISA3}\r\nFOO*BUR/S*A/B~\r\n");

throws_ok { $O->get } qr/unique/, 'delimiter collision noticed';

$O = X12::Schema::TokenSource->new(buffer => "FOO*BUR/S*A/B~\r\n");

throws_ok { $O->get } qr/ISA/, 'missing ISA noticed';
