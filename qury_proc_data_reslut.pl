#!/usr/bin/perl -w

use strict;
use Time::Local;
use POSIX qw(strftime);
use CGI;
use IO::Socket;
use CGI::Carp qw(fatalsToBrowser);


my $q = new CGI;
my $host = $q->param ('ip');
my $port = $q->param ('port');
my $docid = $q->param ('docid');
my $day_from = $q->param ('day_from');
my $day_to = $q->param ('day_to');

my $verbose = 1;
my ($tm_f, $tm_t, $n_day) = ();
my ($year, $month, $today);

(defined $day_from and 10 == length $day_from) or $day_from = '1980-01-01';

if (not (defined $day_to and 10 == length $day_to)) {
  my ($cur_sec, $cur_min, $cur_hour, $cur_mday, $cur_mon, $cur_year, $cur_wday, $cur_yday, $cur_isdst) =  localtime (time);
  $day_to = sprintf ("%04d-%02d-%02d", $cur_year + 1900, $cur_mon +1, $cur_mday);
}

($year, $month, $today) = split /\-/, $day_from;
$tm_f = timelocal (0, 0, 0, $today + 0, $month - 1, $year - 1900);

($year, $month, $today) = split /\-/, $day_to;
$tm_t = timelocal (0, 0, 0, $today + 0, $month - 1, $year - 1900);

$tm_f > $tm_t and show_err_msg ("day time from to error.");

$host =~ /^(?:\d{1,3}\.){3}\d{1,3}$/m or show_err_msg ("IP is NOT legal.");
$port =~ /^\d+$/m or show_err_msg ("PORT is NOT legal.");
$docid =~ /^\d+$/m or $docid =~ /^http\:\/\//m or show_err_msg ("docid or local is NOT legal.");

my $remote = IO::Socket::INET->new (Proto  => "tcp",
                                 PeerAddr => $host,
                                 PeerPort => $port)
or show_err_msg ("Couldn't connect to $host:$port\n$!\n$@\n");

$remote->send (wrap ($tm_f, $tm_t, $docid)) or show_err_msg ("Couldn't send: $!\n$@\n");
$remote->send ($docid) or show_err_msg ("Couldn't send: $!\n$@\n");

my $answer = <$remote> || '---';
my $response = unwrap ($answer);

print $q->header (-charset => 'gb2312', -type => 'text/plain');
print "\tYou use $docid query data from $host on port $port ($day_from --> $day_to):\n\n\n";

# print "$response";
if ("---" eq substr $response, 1, 3) {
  print ">> $response\n";
} else {
	my $v_start = -1;
	while ($response = <$remote>) {
		$v_start = index $response, '--';
		last if -1 != $v_start;
	}
	print substr $response, $v_start;
}

print "$_" while (<$remote>);

close $remote;

exit;

sub wrap {
	my ($tmp_f, $tmp_t, $data) = @_;
	my $header = pack ("a8l2i", 'PRCTL3.0', $tmp_f, $tmp_t, length $data);

	return $header; 
}

sub unwrap {
	my ($packet) = @_;
	my ($checksum, $count, $rcv_data) = unpack "a8iA*", $packet;

	$checksum eq 'PRCTL3.0' or show_err_msg ("return protocal error");
	-6006 == $count and show_err_msg ("hits nothing");
#	$count > 0 or show_err_msg ("return error code: $count");

	return $rcv_data;
}

sub show_err_msg {
	print $q->header (-charset => 'gb2312', -type => 'text/html');
	print "<button onclick=\"location.href='/query_proc_data.html\'\">return<\/button>";

	my ($msg) = @_;
	die "$msg";
}

__END__

# html 

<html>
	<head>
		<meta http-equiv="Content-Type" content="text/html; charset=gb2312" />
		<link type="text/css" rel="stylesheet" href="/tooltip/themes/3/tooltip.css" />
		<script type="text/javascript" src="/tooltip/themes/3/tooltip.js"></script>
		<title>query proc data use locaid</title>
	</head>
	<body>
		<h1>proccess data query site</h1>
		<p>This page is bulit for you guys to query proccessed data.</p>
		<hr noshade color="blue">
		<form action="/cgi-bin/idx_bak_data_query.pl" method="POST">
			<table style="margin-left:auto;margin-right:auto">
				<tr>
					<td>ip: </td>
					<td style="text-align:left"><input type="text" name="ip"  onmouseover="tooltip.pop(this, '<h3>IP / PORT 对应哪套系统？</h3>xxx.xxx.xxx.xxx:xxx是环境1</br>xxx.xxx.xxx.xxx:xxx是环境2</br>xxx.xxx.xxx.xxx:xxx是环境3</br>xxx.xxx.xxx.xxx:xxx是环境4<h4>注意：</h4>1. 只有这四套系统</br>2. 如果最新数据没查到，联系我更新索引')" ></td>
				</tr>
				<tr>
					<td>port: </td>
					<td style="text-align:left"><input type="text" name="port"  onmouseover="tooltip.pop(this, '<h3>IP / PORT 对应哪套系统？</h3>xxx.xxx.xxx.xxx:xxx是环境1</br>xxx.xxx.xxx.xxx:xxx是环境2</br>xxx.xxx.xxx.xxx:xxx是环境3</br>xxx.xxx.xxx.xxx:xxx是环境4<h4>注意：</h4>1. 只有这四套系统</br>2. 如果最新数据没查到，联系我更新索引')" ></td>
				</tr>
				<tr>
					<td>local(id): </td>
					<td style="text-align:left"><input type="text" name="localid"  onmouseover="tooltip.pop(this, '<h3>支持docid和url对应的URL</h3>1. dicid是纯数字</br>2. docid对应的URL必须以http://开头（小写）</br>3. 除1、2外认为是非法输入，我过滤了。</br>4. 若没有查到结果，则返回码是85：hit nothing.</br>5. 结果以处理时间排序，能看到文件名（带ddd数据）')" ></td>
				</tr>
				<tr>
					<td>day from: </td>
					<td style="text-align:left"><input type="date" name="day_from" onmouseover="tooltip.pop(this, '<h3>日期过滤：</h3>1. 起始不选则日期则默认是1970-01-01</br>2. 终止日期不选则默认是今天</br>3. 起始提起比终止日期还晚则日期反转。</br>4.起始和终止日期都是闭区间（包括终止日期）.<h4>TIPS:</h4> 请尽量使用日期过滤，否则返回的数据略大（几十M）')" ></td>
				</tr>
				<tr>
					<td>day to: </td>
					<td style="text-align:left"><input type="date" name="day_to"  onmouseover="tooltip.pop(this, '<h3>日期过滤：</h3>1. 起始不选则日期则默认是1970-01-01</br>2. 终止日期不选则默认是今天</br>3. 起始提起比终止日期还晚则日期反转。</br>4.起始和终止日期都是闭区间（包括终止日期）.<h4>TIPS:</h4> 请尽量使用日期过滤，否则返回的数据略大（几十M）')" ></td>
				</tr>
				<tr>
					<td><br><input type="submit"></td>
					<td style="text-align:right"><br><input type="reset"></td>
				</tr>
  			</table>
		</form>  
	</body>
</html>

