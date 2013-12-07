#!/usr/bin/perl -w

use strict;
use Mail::Sendmail;

2 == 0 + @ARGV or die "pls feed 2 args, 1st is subject, 2nd is content file";

my %mail = (
	server	=> 'smtp.xxxxxxx.com:25',
	auth    => {user => 'char6ming@xxxxxxx.com', password => '', method => 'LOGIN', required => 1},
	From	=> 'char6ming@xxxxxxx.com',
);

$mail{To} = 'someone@xxxxxxx.com,char6ming@xxxxxxx.com';
$mail{Cc} = 'someone@xxxxxxx.com,char6ming@xxxxxxx.com';

$mail{Subject} = shift @ARGV;

{
	local $/ = undef;
	$mail{Message} = <>;
}

sendmail (%mail) or die $Mail::Sendmail::error;
print "OK. Log says:\n", $Mail::Sendmail::log;

__END__
