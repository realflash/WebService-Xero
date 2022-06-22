use warnings;
use strict;
use Pod::Html;						# makes pod2html available
use File::Find;
use FindBin qw($RealBin);
use File::Basename;
use Path::Class;
use File::Path qw(make_path);

my $output_dir = "html";
my $source_dir = "lib";
my $temp_dir ="tmp";
unless(-d "$RealBin/$output_dir")
{
	unless(mkdir "$RealBin/$output_dir") {
        die "Unable to create $RealBin/$output_dir\n";
    }
}
unless(-d "$RealBin/$temp_dir")
{
	unless(mkdir "$RealBin/$temp_dir") {
        die "Unable to create $RealBin/$temp_dir\n";
    }
}

my $files = find(sub { 
	my ($name,$path,$suffix) = fileparse($File::Find::name, (".pod", ".pm"));	# Get the file name part only
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
			make_path($output->parent());
			`pod2html --htmldir=$RealBin/$output_dir --infile=$File::Find::name --outfile=$output --podpath=$RealBin/$source_dir --cachedir=$RealBin/$temp_dir`
		}
	}
}, "$RealBin/$source_dir");
