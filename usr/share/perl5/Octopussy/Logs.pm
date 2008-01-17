=head1 NAME

Octopussy::Logs - Octopussy Logs module

=cut

package Octopussy::Logs;

use strict;
use Octopussy;

my $WIZARD_NB_LINES = 20;

=head2 Device_List($devices)

Returns Device List

=cut

sub Device_List($)
{
	my $devices = shift;
	my @devs = ();
	my %hash_dev;
	
	foreach my $d (AAT::ARRAY($devices))
  {
    push(@devs, (($d !~ /group (.+)/) ? $d : Octopussy::DeviceGroup::Devices($1)));
  }
	foreach my $d (@devs)
  {
		if ($d =~ /-ANY-/i)
		{
			foreach my $e (Octopussy::Device::List())
      {
        $e =~ s/ /_/g;
        $hash_dev{$e} = 1;
      }
		}
		else
		{
			$d =~ s/ /_/g; 
			$hash_dev{$d} = 1; 
		}
	}
	
	return (%hash_dev);
}

=head2 Service_List($services)

Returns Service List

=cut

sub Service_List($)
{
	my $services = shift;
	my %hash_serv;

	foreach my $s (AAT::ARRAY($services))
  {
		if ($s =~ /-ANY-/i)
		{
			foreach my $e (Octopussy::Service::List())
      {
        $e =~ s/ /_/g;
        $hash_serv{$e} = 1;
      }
		}
		else
		{
    	$s =~ s/ /_/g;
			$hash_serv{$s} = 1;
		}
  }		
	
	return (%hash_serv);
}

=head2 Get_Directories($dir)

Gets Logs Directories

=cut

sub Get_Directories($)
{
  my $dir = shift;

	opendir(DIR, $dir);
	my @dirs = grep !/^\./, readdir(DIR);
	closedir(DIR);

	return (@dirs);
}

=head2 Init_Directories($device)

Inits Logs Directories for Device '$device'

=cut

sub Init_Directories($)
{
	my $device = shift;
	
	my $storage = Octopussy::Storage::Default();
	my $incoming = Octopussy::Storage::Directory($storage->{incoming});
	my $unknown = Octopussy::Storage::Directory($storage->{unknown});
	Octopussy::Create_Directory("$incoming/$device/Incoming/");
	Octopussy::Create_Directory("$unknown/$device/Unknown/");
}

=head2 Remove_Directories($device)

Removes Logs Directories for Device '$device'

=cut

sub Remove_Directories($)
{
	my $device = shift;
	
	my $conf = AAT::XML::Read(Filename($device));
  my $storage = Octopussy::Storage::Default();
  my $incoming = Octopussy::Storage::Directory($storage->{incoming});
  my $unknown = Octopussy::Storage::Directory($storage->{unknown});
	my $known = Octopussy::Storage::Directory($storage->{known});
	`rm -rf "$incoming/$device/"`;
	`rm -rf "$unknown/$device/"`;
	`rm -rf "$known/$device/"`;
	foreach my $k (keys %{$conf})
	{
		if ($k =~ /^storage_.+$/)
		{
			my $dir = Octopussy::Storage::Directory($conf->{$k});
			`rm -rf "$dir/$device/"`;
		}
	}
}

=head2 Files($devices, $services, $start, $finish)

Get logs files from '$services' on devices '$devices' 
between '$start' & '$finish' (don't get Incoming/Unknown logs files)

=cut
 
sub Files($$$$)
{
	my ($ref_devices, $ref_services, $start, $finish) = @_;
	my $start_year = $start->{year}*100000000;
	my $start_month = $start_year + $start->{month}*1000000;
	my $start_day = $start_month + $start->{day}*10000;
	my $start_num = $start_day + $start->{hour}*100 + $start->{min};
	my $finish_year = $finish->{year}*100000000;
	my $finish_month = $finish_year + $finish->{month}*1000000;
	my $finish_day = $finish_month + $finish->{day}*10000;
	my $finish_num = $finish_day + $finish->{hour}*100 + $finish->{min};
	my @list = ();
	my %devs = Device_List($ref_devices);
	my %servs = Service_List($ref_services);

	foreach my $dev (sort keys %devs)
  {
		foreach my $s (sort (Octopussy::Device::Services($dev)))
		{
			if (AAT::NOT_NULL($servs{$s}))
			{
				my $dir = Octopussy::Storage::Directory_Service($dev, $s);
				my $dconf =  Octopussy::Device::Configuration($dev);
				foreach my $y (Get_Directories("$dir/$dev/$s"))
				{
					my $num_year = $y*100000000;
					if (($start_year <= $num_year) && ($num_year <= $finish_year))
					{
						foreach my $m (Get_Directories("$dir/$dev/$s/$y"))
						{
							my $num_month = $num_year + $m*1000000;
							if (($start_month <= $num_month) && ($num_month <= $finish_month))
							{
								foreach my $d (Get_Directories("$dir/$dev/$s/$y/$m"))
								{
									my $num_day = $num_month + $d*10000;
									if (($start_day <= $num_day) && ($num_day <= $finish_day))
									{
										my @files = 
											AAT::FS::Directory_Files("$dir/$dev/$s/$y/$m/$d", qr/msg_/);
										foreach my $f (@files)
										{		
											my $num = ($num_day + $1*100 + $2)	
												if ($f =~ /msg_(\d{2})h(\d{2})/);
											push(@list, "$dir/$dev/$s/$y/$m/$d/$f")
												if (($start_num <= $num) && ($num <= $finish_num));
										}
									}
								}
							}
						}
					}
				}
			}
		}
	}
	
	return (\@list);
}

=head2 Get($devices, $services, $start, $finish)

Get logs lines from '$services' on devices '$devices'
between '$start' & '$finish'

=cut
 
sub Get($$$$$$$)
{
	my ($devices, $services, $start, $finish, $re_incl, $re_excl, $limit) = @_;

	my $files = Files($devices, $services, $start, $finish);
	my @logs = ();
	my $counter = 0;
	foreach my $f (sort (AAT::ARRAY($files)))
	{
  	open(FILE, "zcat '$f' |");
  	while (<FILE>) 
    {
			my $line = $_;
			my $match = 1;
			foreach my $inc (AAT::ARRAY($re_incl))
				{ $match = 0	if (($inc ne "") && ($line !~ /$inc/i)); }
			foreach my $excl (AAT::ARRAY($re_excl))
				{ $match = 0	if (($excl ne "") && ($line =~ /$excl/i)); }
			if ($match)
			{
				$counter++; 
				push(@logs, $_);
			}
			last  if ($counter >= $limit); 
		}
		close(FILE);
		last	if ($counter >= $limit);
	}
	my @sorted_logs = sort @logs;

	return (\@sorted_logs);
}

=head2 Incoming_Files($device)

Returns list of 'Incoming Files'

=cut

sub Incoming_Files($)
{
	my $device = shift;

	my $dconf = Octopussy::Device::Configuration($device);
	my $dir =  Octopussy::Storage::Directory_Incoming($device);
	Octopussy::Create_Directory("$dir/$device/Incoming/");
	my @files = `find "$dir/$device/Incoming/" -name "msg_*.log"`;
	
	return (sort @files);
}

=head2 Unknown_Files($device, $first_file)

Returns list of 'Unknown Files'
(lines of these files doesn't match any defined message)

=cut

sub Unknown_Files
{
	my ($device, $first_file) = @_;
	my @unknown = ();

	my $dconf = Octopussy::Device::Configuration($device);
	my $dir = Octopussy::Storage::Directory_Unknown($device);
	Octopussy::Create_Directory("$dir/$device/Unknown/");
	my @files = `find "$dir/$device/Unknown/" -name "msg_*.log.gz"`;	
	my @sorted_files = sort @files;
	return (@sorted_files)	if (!defined $first_file);
	
	foreach my $f (@sorted_files)	
		{ push(@unknown, $f)	if ($f ge $first_file); }

	return (@unknown);
}

=head2 Unknown_Number($device)

Returns number of unknown log messages for device '$device'

=cut
  
sub Unknown_Number($)
{
	my $device = shift;

	my @files = Unknown_Files($device);
	my ($total, $nb) = (0, 0);
	foreach my $f (sort @files)
	{
		chomp($f);
		$nb = `zcat "$f" | wc -l`; 
		chomp($nb);
		$total += $nb	if ($nb >= 0);
		last	if ($total > $WIZARD_NB_LINES);
	}
	
	return ($total);
}

=head2 Remove($device, $log)

Removes Log '$log' from Unknown Logs for Device '$device'

=cut

sub Remove($$)
{
	my ($device, $log) = @_;
	my $match = 0;
	my @files = Unknown_Files($device);
	foreach my $f (sort @files)
  {
    chomp($f);
		my @logs = ();
    open(FILE, "zcat '$f' |");
    while (<FILE>)
    { 
			if ($_ =~ /^$log\s*$/)
				{ $match = 1; }
			else
				{ push(@logs, $_); }
		}
    close(FILE);
		unlink($f);
		open(NEW, "|gzip > $f");
		foreach my $l (@logs)
			{ print NEW $l; }	
		close(NEW);
		#last	if ($match);
	}
}

=head2 Remove_Minute($device, $year, $month, $day, $hour, $min)

Removes 1 minute of Log File for Device '$device'

=cut

sub Remove_Minute($$$$$$)
{
	my ($device, $year, $month, $day, $hour, $min) = @_;

	my @files = Unknown_Files($device);
	foreach my $f (sort @files)
  {
		chomp($f);
		unlink($f)	
			if ($f =~ /.+Unknown\/$year\/$month\/$day\/msg_${hour}h$min/);
	}
}

1;

=head1 AUTHOR

Sebastien Thebert <octo.devel@gmail.com>

=cut