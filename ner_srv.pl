#!/usr/bin/perl -w

use strict;
use warnings;
use IO::Socket;
use threads;
use Thread::Queue;
use POSIX qw(strftime);
use Time::HiRes;
use POE qw(Component::Server::TCP);

our $THREADS = 20;
my @branch_queues = map {new Thread::Queue} 1 .. $THREADS;
my %names = ();

@ARGV = ("./name_tf.dat");

print strftime ("%Y/%m/%d %H:%M:%S", localtime), " Now start to load dictionary...\n";

while (<>) {
	chomp;

	next if /\,/;
	/^\s*(.+) ==> (\d+)$/s;
	my $raw_name_len = length $1;
	next if 1 == $raw_name_len;
	2 == $raw_name_len and $1 =~ m/^[a-z]{2}$/i and next;
	$names{quotemeta ($1)} = $2;
}

my $regex = join '|', sort {length $b <=> length $a} keys %names;

print strftime ("%Y/%m/%d %H:%M:%S", localtime), " load dictionary finished ", scalar keys %names, " entrys in all.\n\n";

POE::Component::Server::TCP->new (
				Port => 6666,
				ClientConnected => sub {
					print "got a connection from $_[HEAP]{remote_ip}\n";
#					$_[HEAP]{client}->put("Smile from the server!");
    				},
    				ClientInput => sub {
      					my ($checksum, $client_len, $client_input) = unpack ("a8ia*", $_[ARG0]);
      					"NER_iSRV" eq $checksum or print "checksum error.\n" and $_[HEAP]{client}->put (pack ("a8i", "NER_iSRV", -1)) and return;
      					$client_len > 1 or print "client_len $client_len error.\n" and $_[HEAP]{client}->put (pack ("a8i", "NER_iSRV", -2)) and return;      
					print strftime ("%Y/%m/%d %H:%M:%S", localtime), " Now begain proc:\n$client_input\n";
					my @matches = ($client_input =~ /($regex)/g);
					(0 + @matches) > 0 or print "$client_input have no name.\n" and $_[HEAP]{client}->put (pack ("a8i", "NER_iSRV", -3)) and return;

      					{	
						local $" = '+';
						$_[HEAP]{client}->put (pack ("a8ia*", "NER_iSRV", length "@matches\n", "@matches\n"));
					}

					print strftime ("%Y/%m/%d %H:%M:%S", localtime), " proc finished\n";
				},
				ClientDisconnected => sub {
					print "$_[HEAP]{remote_ip} disconnected\n\n";
				},
);

POE::Kernel->run ();
exit (0);
