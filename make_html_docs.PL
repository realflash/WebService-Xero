use warnings;
use strict;
use Pod::Html;
use File::Find;
use FindBin qw($RealBin);
use File::Basename;
use Path::Class;
use File::Path qw(make_path);

my $output_dir = "html";
my $source_dir = "lib";
unless(-d $output_dir)
{
	unless(mkdir $output_dir) {
        die "Unable to create $output_dir\n";
    }
}

my $files = find(sub { 
	my ($name,$path,$suffix) = fileparse($File::Find::name, (".pod", ".pm"));	# Get the file name part only
	#~ print "$path $name $suffix\n";
	unless(-d $File::Find::name)
	{	# Ignored directories
		if($suffix)
		{	# Ignored files not ending with suffixes likely to contain POD
			print "Converting ".$File::Find::name." to HTML\n";
			my $relative;
			my $current = Path::Class::Dir->new($path);
			while($current->basename ne $source_dir)
			{
				unshift(@$relative, $current->basename);
				$current = $current->parent;
			}
			my $output = Path::Class::File->new($RealBin, $output_dir, @$relative, $name.".html");
			print "Writing $output\n";
			make_path($output->parent());
			#~ print "--htmldir=$RealBin/$output_dir --infile=$File::Find::name --outfile=$output";
			pod2html("pod2html", "--podpath=$RealBin/$source_dir", "--htmldir=$RealBin/$output_dir", "--infile=".$File::Find::name, "--outfile=$output");
		}
	}
}, "$RealBin/$source_dir");
