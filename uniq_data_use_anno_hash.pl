#!/usr/bin/perl -w

use strict;
use warnings;
use IO::Socket;
use threads;
use threads::shared;
use Thread::Queue;
use POSIX qw(strftime);
use Time::HiRes qw(usleep);
use Tie::Hash::Indexed;
use Digest::MD5;
use Data::Dumper;
use Fcntl qw(SEEK_SET);
use Storable;
# use POE qw(Component::Server::TCP);

our $THREADS = 60;

my ($bak_xml_sum, $err_sum, $option, $host, $port) = ();
my @branch_queues = map {new Thread::Queue} 1 .. $THREADS;
# my @datas = map {&mormal_hash ()} 1 .. $THREADS;
my @datas: shared = ();
my @no_redundancy_data_order = ();

my ($raw_file, $idx_data, $no_redundancy_data) = (); 
# share ($idx_data);
# share ($no_redundancy_data);

$raw_file = retrieve ('raw_file_list');
$idx_data = retrieve ('idx_data');
$no_redundancy_data = retrieve ('no_redundancy_data');

# tie my %hash, 'Tie::Hash::Indexed';

my $usage = q {
Usage : this_proc -e | -f IP PORT snd_file.lst
	send the snd_bak_dat_files to the host IP on port PORT, only
	exactly choose one option:

	-e: extract specific tags
	-f: filter specific tags

NOTE : ONLY support -f option this version, sorry.

};

0 + @ARGV == 3 or die "$usage\n";
# $option = shift @ARGV and ('-e' eq $option or '-f' eq $option) or die "pls feed correct opetion.\n";
$host = shift @ARGV and $host =~ m/(?:\d+?\.){3}\d+?/ or die 'pls give correct IP';
$port = shift @ARGV and $port =~ m/\d+?/ or die 'pls give correct PORT';
my @choose_files = <>;
# print "@ARGV", "\n";

# NOTE : ONLY support -f option this version, sorry.
# '-f' eq $option or die "\n\tNOTE : ONLY support -f option this version, sorry.\n\n";

sub ordered_hash (%) {
    tie my %hash => 'Tie::Hash::Indexed';
    share (%hash);
    %hash = @_;
    \%hash
}

sub mormal_hash (%) {
   my %hash:shared = @_;
    \%hash
}

sub worker {
	my $idx = threads->tid % $THREADS;
	my ($branch_queues, $root_datas) = @_;
	while (defined (my $work = $$branch_queues[$idx]->dequeue ())) {
		my ($docid_len) = unpack("i", $work);
		my (undef, $docid, $file_idx, $data_pos, $all_len, undef, $xml_len, $xml) = unpack ("ia$docid_len iiia54ia*", $work);
# 		($xml) = unpack ("a$xml_len", $xml);
# 		print "\n$xml\n";
# 		print "\n$xml_len\n";

		$xml =~ s#<fresh_time><!\[CDATA\[\d+?\]\]></fresh_time>##s;

		my $xml_md5 = Digest::MD5::md5_hex ($xml);

# 		if ('8680713309700589697' eq $docid)  {
# 
# 		      print 'hits ', $xml_md5, " \n";
# 		}
		
		defined $$root_datas[$docid % $THREADS] or $$root_datas[$docid % $THREADS] = mormal_hash ();

		defined $$root_datas[$docid % $THREADS]{$docid} or $$root_datas[$docid % $THREADS]{$docid} = ordered_hash ();

		defined $$root_datas[$docid % $THREADS]{$docid}{$xml_md5} and delete $$root_datas[$docid % $THREADS]{$docid}{$xml_md5};
		
		$$root_datas[$docid % $THREADS]{$docid}{$xml_md5} = pack ("iii", $file_idx, $data_pos, $all_len);
# 		$$root_datas[$docid % $THREADS]{$docid}{$xml_md5} = $xml;

#		print $$root_datas[$docid % $THREADS]{$docid}{$xml_md5}, "\n\n"; 
#		print "send q$idx ok:",  $$branch_queues[$idx]->pending (), "\n";
	}

#	$$branch_queues[$idx]->enqueue (undef);
#        print "|$idx|", threads->tid, "| exit ._.\n";	
}


my @work_pool = map {threads->create (\&worker, \@branch_queues, \@datas)} 1 .. $THREADS;

$bak_xml_sum = 0;
$err_sum = 0;

foreach my $file_idx (0..$#choose_files) {
	chomp ($choose_files[$file_idx]);
	my ($fhd, $buf) = (undef, undef);

	unless (open ($fhd, "<:raw:perlio", $choose_files[$file_idx])) {
		print "can NOT open $choose_files[$file_idx]: $!\n";

		next;
	}

	print "Now begain send $choose_files[$file_idx] ", strftime ("%Y/%m/%d %H:%M:%S", localtime), "\n";;

	while (4 == read ($fhd, $buf, 4)) {
			++$bak_xml_sum;

#			last if eof ($fhd);

			my ($all_len, $record, $xml_len, $xml, $data_pos) = ();
			($all_len) = unpack ("i", $buf);

			$data_pos = tell ($fhd) or die "cant not tell $!\n";

			$all_len == read ($fhd, $record, $all_len) or ++$err_sum and last;

			8 == read ($fhd, $buf, 8) or ++$err_sum and last;

			(undef, $xml_len, undef) = unpack ("a54ia*", $record);

			$xml = substr ($record, 58, $xml_len);

#			next if $xml !~ m/ fun=\"gs_/gis;

			my $docid = $1 if $xml =~ m/<docid><\!\[CDATA\[(\d+?)\]\]><\/docid>/s;

			defined $docid or ++$err_sum and next;

			my $docid_len = length $docid;

			if ($branch_queues[$docid % $THREADS]->pending () > 1024) {

				usleep (100000);
			}

			$branch_queues[$docid % $THREADS]->enqueue (pack ("ia$docid_len iiia$all_len", $docid_len, $docid, $file_idx, $data_pos, $all_len, $record));
	}

	close ($fhd);

	print "Send $choose_files[$file_idx] finished $bak_xml_sum in all, err $err_sum ", strftime ("%Y/%m/%d %H:%M:%S", localtime), "\n";
}

$_->enqueue (undef) for @branch_queues;

store \@datas, 'idx_data';
store \@choose_files, 'raw_file_list';

$_->join for @work_pool;


#  test
my $query_docid = '8680713309700589697';
my $hits_uniq_sum = 0;
my $all_data = "\n" . 'query docid ==> ' . $query_docid . " \n";
# 
# print Dumper (@datas); 
# 
# print Dumper ($datas[$query_docid % $THREADS]{$query_docid});

for my $entry (values %{$datas[$query_docid % $THREADS]{$query_docid}}) {
    ++$hits_uniq_sum;
    my ($file_idx, $data_pos, $all_len) = unpack ("iii", $entry);

    my ($fhd, $buf) = (undef, undef);

    unless (open ($fhd, "<:raw:perlio", $choose_files[$file_idx])) {
		print "can NOT open $choose_files[$file_idx]: $!\n";

		next;
    }

    seek ($fhd, $data_pos, SEEK_SET) or warn "can NOT seek pos $data_pos in $choose_files[$file_idx]: $?" and close ($fhd) and next;
    
    $all_len == read ($fhd, $buf, $all_len) or close ($fhd) and warn "can NOT read $choose_files[$file_idx]: $?" and next;

    $all_data .= ('-------' . $choose_files[$file_idx] . '-------' . "\n" . $buf . "\n");

    close ($fhd);
}

print $all_data, " $hits_uniq_sum in all \n";


my ($uniq_docid_sum, $uniq_xml_sum) = (0, 0);

for my $idx (0..$#datas) {
      defined $datas[$idx] or next;
      for my $docid (keys %{$datas[$idx]}) {
	    ++$uniq_docid_sum;
# 	    defined $id_hash or last;
	    for my $md5s (keys %{$datas[$idx]{$docid}}) {
		    ++$uniq_xml_sum;
		    push @no_redundancy_data_order, $datas[$idx]{$docid}{$md5s};

# 		    print $md5s, ' ==> ', $datas[$idx]{$docid}{$md5s}, "\n\n";
	    }
      }
}

store \@no_redundancy_data_order, 'no_redundancy_data';

print $uniq_docid_sum, ' |', $uniq_xml_sum, '| ', "\n";

print "Send finished $bak_xml_sum in all, err $err_sum ", strftime ("%Y/%m/%d %H:%M:%S", localtime), "\n";

exit (0);

__END__
