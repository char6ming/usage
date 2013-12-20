#!/usr/bin/perl -w

use strict;
use warnings;
use IO::Socket;
use threads;
use Thread::Queue;
use POSIX qw(strftime);
use Time::HiRes qw(usleep);

select STDOUT;
$| = 1;

our $THREADS = 32;
my $out_mutex :shared;

# ('-f', 'XXX.XXX.XXX.XXX', '41005')
my ($option, $host, $port) = ();
my @branch_queues = map {new Thread::Queue} 1 .. $THREADS;

my $usage = q {
Usage : this_proc -e | -f IP PORT snd_file.lst
	send the snd_bak_dat_files to the host IP on port PORT, only
	exactly choose one option:

	-e: extract specific tags
	-f: filter specific tags

NOTE : ONLY support -f option this version, sorry.

};

# my $out_dat_fh = undef;
# my $out_dat_file = './tiny_vd_null_pic.dat';
# open ($out_dat_fh, ">:raw:perlio", $out_dat_file) or die "can NOT open $out_dat_file: $!";

0 + @ARGV == 3 or die "$usage\n";
# $option = shift @ARGV and ('-e' eq $option or '-f' eq $option) or die "pls feed correct opetion.\n";
$host = shift @ARGV and $host =~ m/(?:\d+?\.){3}\d+?/ or die 'pls give correct IP';
$port = shift @ARGV and $port =~ m/\d+?/ or die 'pls give correct PORT';
my @choose_files = <>;
# print "@ARGV", "\n";

# NOTE : ONLY support -f option this version, sorry.
# '-f' eq $option or die "\n\tNOTE : ONLY support -f option this version, sorry.\n\n";

sub worker {
	my $idx = threads->tid % $THREADS;
	my ($branch_queues) = @_;
	my $pic_null_sum;

#	while ((print 'pending ', $$branch_queues[$idx]->pending (), " \n") and (my $work = $$branch_queues[$idx]->dequeue)) {
	while (my $work = $$branch_queues[$idx]->dequeue) {
		my ($xml_len, $xml) = unpack ("ia*", $work);
		my $tmp_buf = $1 if $xml =~ m#<xxxpos>(.+?)<\/xxxpos>#s;

		defined $tmp_buf or print 'can not find xxxpos', "\n", $xml, "\n"  and next;

#		print "\n$xml\n";
#		print "\n$xml_le:

		my $pic_frag = $1 if $tmp_buf =~ m#<pic><\!\[CDATA\[(.*?)\,#s;

		defined $pic_frag and 0 < length $pic_frag and next;

		$xml =~ m#<tiny_video><\!\[CDATA\[\]\]><\/tiny_video>#s or next;

		my $url = $1 if $xml =~ m#<link><\!\[CDATA\[(.+?)\]\]><\/link>#s;

		defined $url or print 'can not find link', "\n", $xml, "\n"  and next;

		++$pic_null_sum;

#        	{
#	               	lock ($out_mutex);

#			my $old_fh = select $out_dat_fh;
#			$| = 1;			
#        	        print pack ("i", $xml_len), $xml;
#			select STDOUT;
#	        }

		my $url_len = length $url;

		$url_len += 2;

		my $snd_buf = pack ("a8isA16siiA$url_len", 'XXXXX2.0', 24 + 4 + $url_len, 3, ' ', 2, 9, $url_len, '1#' . $url);

		while (1) {
	 		my $remote = IO::Socket::INET->new (Proto  => "tcp", PeerAddr => $host, PeerPort => $port) or die ("Couldn't connect to $host:$port\n$!");
	 		$remote->send ($snd_buf) or die ("Couldn't send: $!");

#       			{
#               			lock ($out_mutex);
#					print substr ($snd_buf, 40), "\n";
#       			}

	 		my ($ver, $err_code, $ret_header, $skip_gap) = ();
	 		$remote->read ($ret_header, 12) or  print "recv error: $! |$xml|, try again.\n" and close $remote and usleep (100000) and next;
			($ver, undef) = unpack ("a8i", $ret_header);
			'VIDEO2.0' eq $ver or die ("protocal check error: $ver");

			$remote->read ($ret_header, 18) or die ("recv error: $!");

	 		close $remote;
	 
	 		(undef, undef, $err_code) = unpack ("sa12i", $ret_header);

			0 == $err_code and last;
			-50598 == $err_code and last;

			print 'return errno: ', $err_code, ' retry!!', "\n"; 
	 
			usleep (1000);
		}

	}

#	{
#		lock ($out_mutex);
#		print 'pic_null_sum: ', $pic_null_sum, "\n";
#	}

#	$$branch_queues[$idx]->enqueue (undef);

	return $pic_null_sum;
}

my @work_pool = map {threads->create (\&worker, \@branch_queues)} 1 .. $THREADS;

my $data_sum = 0;

foreach my $file (@choose_files) {
	chomp ($file);
	my ($fhd, $buf) = (undef, undef);

	unless (open ($fhd, "<:raw:perlio", $file)) {
		print "can NOT open $file: $!";

		next;
	}

	print "Now begain send $file ", strftime ("%Y/%m/%d %H:%M:%S", localtime), "\n";;

	while (4 == read ($fhd, $buf, 4)) {
			my ($xml_len, $xml) = ();
			($xml_len) = unpack ("i", $buf);

			$xml_len == read ($fhd, $xml, $xml_len) or last;

			++$data_sum;

			my $finger = $1 if $xml =~ m#<finger><\!\[CDATA\[(\d+?)\]\]><\/finger>#s;

			defined $finger or print 'can not find finger', "\n", $xml, "\n" and next;

			while ($branch_queues[$finger % $THREADS]->pending () > 1024) {

				usleep (1000);
			}

			$branch_queues[$finger % $THREADS]->enqueue (pack ("ia$xml_len", $xml_len, $xml));

#			read ($fhd, $buf, 8) or last;
	}

	close ($fhd);

	print "Send $file finished ", strftime ("%Y/%m/%d %H:%M:%S", localtime), "\n";
}

$_->enqueue (undef) for @branch_queues;

my @result = ();

push @result, $_->join for @work_pool;

# close $out_dat_fh;

my $rt_sum = 0;

$rt_sum += $_ for @result;

print 'the reuslt is null pic sum: ', $rt_sum, ' data sum: ',  $data_sum, " \n";

exit (0);

__END__
