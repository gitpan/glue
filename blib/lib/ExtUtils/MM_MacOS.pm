#   MM_MacOS.pm
#   MakeMaker default methods for MacOS
#   This package is inserted into @ISA of MakeMaker's MM before the
#   built-in ExtUtils::MM_Unix methods if MakeMaker.pm is run under MacOS.
#
#   Author:  Matthias Neeracher <neeri@iis.ee.ethz.ch>

package ExtUtils::MM_MacOS;
unshift @MM::ISA, 'ExtUtils::MM_MacOS';

use Config;
require Exporter;
use File::Basename;
use vars qw(%make_data);

Exporter::import('ExtUtils::MakeMaker', '$Verbose', '&neatvalue');

=head1 NAME

ExtUtils::MM_MacOS - methods to override UN*X behaviour in ExtUtils::MakeMaker

=head1 SYNOPSIS

 use ExtUtils::MM_MacOS; # Done internally by ExtUtils::MakeMaker if needed

=head1 DESCRIPTION

MM_MacOS currently only produces an approximation to the correct Makefile.

=cut

sub ExtUtils::MM_MacOS::new {
    my($class,$self) = @_;
    my($key);
    my($was_required) = (caller(2))[3] eq '(eval)';
    my($cwd) = cwd();

    print STDOUT "Mac MakeMaker (v$ExtUtils::MakeMaker::VERSION)\n" if $Verbose;
    if (-f "MANIFEST" && ! -f "Makefile.mk"){
	ExtUtils::MakeMaker::check_manifest();
    }

    mkdir("Obj", 0777) unless -d "Obj";
    
    $self = {} unless (defined $self);

    my(%initial_att) = %$self; # record initial attributes

    if (defined $self->{CONFIGURE}) {
	if (ref $self->{CONFIGURE} eq 'CODE') {
	    $self = { %$self, %{&{$self->{CONFIGURE}}}};
	} else {
	    Carp::croak "Attribute 'CONFIGURE' to WriteMakefile() not a code reference\n";
	}
    }

    $class = ++$ExtUtils::MakeMaker::PACKNAME;
    {
	print "Blessing Object into class [$class]\n" if $Verbose>=2;
	ExtUtils::MakeMaker::mv_all_methods("MY",$class);
	bless $self, $class;
	push @Parent, $self;
	@{"$class\:\:ISA"} = 'MM';
    }

    if (defined $Parent[-2]){
	$self->{PARENT} = $Parent[-2];
	my $key;
	for $key (keys %Prepend_dot_dot) {
	    next unless defined $self->{PARENT}{$key};
	    $self->{$key} = $self->{PARENT}{$key};
	    $self->{$key} = $self->catdir("::",$self->{$key})
		unless $self->file_name_is_absolute($self->{$key});
	}
	$self->{PARENT}->{CHILDREN}->{$class} = $self if $self->{PARENT};
    } else {
	$self->parse_args(@ARGV);
    }

    $self->{NAME} ||= $self->guess_name;

    ($self->{NAME_SYM} = $self->{NAME}) =~ s/\W+/_/g;

    $self->init_main();
    $self->init_dirscan();
    $self->init_others();

    push @{$self->{RESULT}}, <<END;
# This Makefile is for the $self->{NAME} extension to perl.
#
# It was generated automatically by MakeMaker version
# $VERSION (Revision: $Revision) from the contents of
# Makefile.PL. Don't edit this file, edit Makefile.PL instead.
#
#	ANY CHANGES MADE HERE WILL BE LOST!
#
#   MakeMaker Parameters:
END

    foreach $key (sort keys %initial_att){
	my($v) = neatvalue($initial_att{$key});
	$v =~ s/(CODE|HASH|ARRAY|SCALAR)\([\dxa-f]+\)/$1\(...\)/;
	$v =~ tr/\n/ /s;
	push @{$self->{RESULT}}, "#	$key => $v";
    }

    # turn the SKIP array into a SKIPHASH hash
    my (%skip,$skip);
    for $skip (@{$self->{SKIP} || []}) {
	$self->{SKIPHASH}{$skip} = 1;
    }
    delete $self->{SKIP}; # free memory

    # We skip many sections for MacOS, but we don't say anything about it in the Makefile
    for (qw/post_initialize const_config tool_autosplit
	    tool_xsubpp tools_other dist macro depend post_constants
	    pasthru c_o xs_c xs_o top_targets linkext 
	    dynamic_bs dynamic_lib static_lib manifypods processPL
	    installbin subdirs dist_basics dist_core
	    dist_dir dist_test dist_ci install force perldepend makefile
	    staticmake test pm_to_blib selfdocument cflags 
	    const_loadlibs const_cccmd
    /) 
    {
	$self->{SKIPHASH}{$_} = 2;
    }
    push @ExtUtils::MakeMaker::MM_Sections, "rulez" 
    	unless grep /rulez/, @ExtUtils::MakeMaker::MM_Sections;
    
    if ($self->{PARENT}) {
	for (qw/install dist dist_basics dist_core dist_dir dist_test dist_ci/) {
	    $self->{SKIPHASH}{$_} = 1;
	}
    }

    # We run all the subdirectories now. They don't have much to query
    # from the parent, but the parent has to query them: if they need linking!
    unless ($self->{NORECURS}) {
	$self->eval_in_subdirs if @{$self->{DIR}};
    }

    my $section;
    foreach $section ( @ExtUtils::MakeMaker::MM_Sections ){
    	next if ($self->{SKIPHASH}{$section} == 2);
	print "Processing Makefile '$section' section\n" if ($Verbose >= 2);
	my($skipit) = $self->skipcheck($section);
	if ($skipit){
	    push @{$self->{RESULT}}, "\n# --- MakeMaker $section section $skipit.";
	} else {
	    my(%a) = %{$self->{$section} || {}};
	    push @{$self->{RESULT}}, "\n# --- MakeMaker $section section:";
	    push @{$self->{RESULT}}, "# " . join ", ", %a if $Verbose && %a;
	    push @{$self->{RESULT}}, $self->nicetext($self->$section( %a ));
	}
    }

    push @{$self->{RESULT}}, "\n# End.";
    pop @Parent;

    $ExtUtils::MM_MacOS::make_data{$cwd} = $self if ($was_required);
    $self;
}

sub skipcheck {
    my($self) = shift;
    my($section) = @_;
    return 'skipped' if $self->{SKIPHASH}{$section};
    return '';
}

=item guess_name

Guess the name of this package by examining the working directory's
name. MakeMaker calls this only if the developer has not supplied a
NAME attribute.

=cut

sub guess_name {
    my($self) = @_;
    use Cwd 'cwd';
    my $name = cwd();
    $name =~ s/.*:// unless ($name =~ s/^.*:ext://);
    $name =~ s#:#::#g;
    $name =~  s#[\-_][\d.\-]+$##;  # this is new with MM 5.00
    $name;
}

=item macify

Translate relative path names into Mac names.

=cut

sub macify {
    my($unix) = @_;
    my(@mac);
    
    foreach (split(/[ \t\n]+/, $unix)) {
	if (m|/|) {
	    $_ = ":$_";
	    s|/|:|g;
	} 
	push(@mac, $_);
    }
    
    return "@mac";
}

=item patternify

Translate to Mac names & patterns

=cut

sub patternify {
    my($unix) = @_;
    my(@mac);
    
    foreach (split(/[ \t\n]+/, $unix)) {
	if (m|/|) {
	    $_ = ":$_";
	    s|/|:|g;
	    s|\*|�|g;
	    $_ = "'$_'" if /[?�]/;
	    push(@mac, $_);
	}
    }
    
    return "@mac";
}

=item init_main

Initializes some of NAME, FULLEXT, BASEEXT, ROOTEXT, DLBASE, PERL_SRC,
PERL_LIB, PERL_ARCHLIB, PERL_INC, INSTALLDIRS, INST_*, INSTALL*,
PREFIX, CONFIG, AR, AR_STATIC_ARGS, LD, OBJ_EXT, LIB_EXT, MAP_TARGET,
LIBPERL_A, VERSION_FROM, VERSION, DISTNAME, VERSION_SYM.

=cut

sub init_main {
    my($self) = @_;
    unless (ref $self){
	ExtUtils::MakeMaker::TieAtt::warndirectuse((caller(0))[3]);
	$self = $ExtUtils::MakeMaker::Parent[-1];
    }

    # --- Initialize Module Name and Paths

    # NAME    = The perl module name for this extension (eg DBD::Oracle).
    # FULLEXT = Pathname for extension directory (eg DBD/Oracle).
    # BASEEXT = Basename part of FULLEXT. May be just equal FULLEXT.
    # ROOTEXT = Directory part of FULLEXT with trailing :.
    ($self->{FULLEXT} =
     $self->{NAME}) =~ s!::!:!g ;		     #eg. BSD:Foo:Socket
    ($self->{BASEEXT} =
     $self->{NAME}) =~ s!.*::!! ;		             #eg. Socket
    ($self->{ROOTEXT} =
     $self->{FULLEXT}) =~ s#:?\Q$self->{BASEEXT}\E$## ;      #eg. BSD:Foo
    $self->{ROOTEXT} .= ":" if ($self->{ROOTEXT});

    # --- Initialize PERL_LIB, INST_LIB, PERL_SRC

    # *Real* information: where did we get these two from? ...
    my $inc_config_dir = dirname($INC{'Config.pm'});
    my $inc_carp_dir   = dirname($INC{'Carp.pm'});

    unless ($self->{PERL_SRC}){
	my($dir);
	foreach $dir (qw(:: ::: :::: :::::)){
	    if ( -f "${dir}config.mac"
		&& -f "${dir}perl.h") {
		$self->{PERL_SRC}=$dir ;
		last;
	    }
	}
	if (!$self->{PERL_SRC} && -f "$ENV{MACPERL}CORE:perl:config.mac") {
	    # Mac pathnames may be very nasty, so we'll install symlinks
	    unlink(":PerlCore", ":PerlLib");
	    symlink("$ENV{MACPERL}CORE:", "PerlCore");
	    symlink("$ENV{MACPERL}lib:", "PerlLib");
	    $self->{PERL_SRC} = ":PerlCore:perl:" ;
	    $self->{PERL_LIB} = ":PerlLib:";
	}
    }
    if ($self->{PERL_SRC}){
	$self->{PERL_LIB}     ||= $self->catdir("$self->{PERL_SRC}","lib");
	$self->{PERL_ARCHLIB} = $self->{PERL_LIB};
	$self->{PERL_INC}     = $self->{PERL_SRC};
    } else {
# hmmmmmmm ... ?
    $self->{PERL_LIB} ||= "$ENV{MACPERL}site_perl";
	$self->{PERL_ARCHLIB} = $self->{PERL_LIB};
	$self->{PERL_INC}     = $ENV{MACPERL};
#    	die <<END;
#On MacOS, we need to build under the Perl source directory or have the MacPerl SDK
#installed in the MacPerl folder.
#END
    }

    $self->{INSTALLDIRS} = "perl";
    $self->{INST_LIB} = $self->{INST_ARCHLIB} = $self->{PERL_LIB};
    $self->{INST_MAN1DIR} = $self->{INSTALLMAN1DIR} = "none";
    $self->{MAN1EXT} ||= $Config::Config{man1ext};
    $self->{INST_MAN3DIR} = $self->{INSTALLMAN3DIR} = "none";
    $self->{MAN3EXT} ||= $Config::Config{man3ext};
    $self->{MAP_TARGET} ||= "perl";

    # make a simple check if we find Exporter
    warn "Warning: PERL_LIB ($self->{PERL_LIB}) seems not to be a perl library directory
        (Exporter.pm not found)"
	unless -f $self->catfile("$self->{PERL_LIB}","Exporter.pm") ||
        $self->{NAME} eq "ExtUtils::MakeMaker";

    # Determine VERSION and VERSION_FROM
    ($self->{DISTNAME}=$self->{NAME}) =~ s#(::)#-#g unless $self->{DISTNAME};
    if ($self->{VERSION_FROM}){
	local *FH;
	open(FH,macify($self->{VERSION_FROM})) or
	    die "Could not open '$self->{VERSION_FROM}' (attribute VERSION_FROM): $!";
	while (<FH>) {
	    chop;
	    next unless /\$([\w:]*\bVERSION)\b.*=/;
	    local $ExtUtils::MakeMaker::module_version_variable = $1;
	    my($eval) = "$_;";
	    eval $eval;
	    die "Could not eval '$eval': $@" if $@;
	    if ($self->{VERSION} = $ {$ExtUtils::MakeMaker::module_version_variable}){
		print "$self->{NAME} VERSION is $self->{VERSION} (from $self->{VERSION_FROM})\n" if $Verbose;
	    } else {
		# XXX this should probably croak
		print "WARNING: Setting VERSION via file '$self->{VERSION_FROM}' failed\n";
	    }
	    last;
	}
	close FH;
    }

    # if your FOO.pm says
    #	$VERSION = substr(q$Revision: 1.4 $, 10);
    # then MM says something like
    #	-DXS_VERSION=\"n.nn \"
    if ($self->{VERSION}) {
	$self->{VERSION} =~ s/^\s+//;
	$self->{VERSION} =~ s/\s+$//;
    }

    $self->{VERSION} = "0.10" unless $self->{VERSION};
    ($self->{VERSION_SYM} = $self->{VERSION}) =~ s/\W/_/g;


    # Graham Barr and Paul Marquess had some ideas how to ensure
    # version compatibility between the *.pm file and the
    # corresponding *.xs file. The bottomline was, that we need an
    # XS_VERSION macro that defaults to VERSION:
    $self->{XS_VERSION} ||= $self->{VERSION};

    # --- Initialize Perl Binary Locations

    # Find Perl 5. The only contract here is that both 'PERL' and 'FULLPERL'
    # will be working versions of perl 5. miniperl has priority over perl
    # for PERL to ensure that $(PERL) is usable while building ./ext/*
    my ($component,@defpath);
    foreach $component ($self->{PERL_SRC}, $self->path(), $Config::Config{binexp}) {
	push @defpath, $component if defined $component;
    }
    $self->{PERL} = "$self->{PERL_SRC}miniperl";
    $self->{FULLPERL} = "$self->{PERL_SRC}perl";
    $self->{MAKEFILE} = "Makefile.mk";
}

=item init_others

Initializes LDLOADLIBS, LIBS

=cut

sub init_others {	# --- Initialize Other Attributes
    my($self) = shift;
    unless (ref $self){
	ExtUtils::MakeMaker::TieAtt::warndirectuse((caller(0))[3]);
	$self = $ExtUtils::MakeMaker::Parent[-1];
    }

    # Compute LDLOADLIBS from $self->{LIBS}
    # Lets look at $self->{LIBS} carefully: It may be an anon array, a string or
    # undefined. In any case we turn it into an anon array:

    # May check $Config{libs} too, thus not empty.
    $self->{LIBS}=[''] unless $self->{LIBS};

    $self->{LIBS}=[$self->{LIBS}] if ref \$self->{LIBS} eq SCALAR;
    my($libs);
    foreach $libs ( @{$self->{LIBS}} ){
	$libs =~ s/^\s*(.*\S)\s*$/$1/; # remove leading and trailing whitespace
	# Any Mac library will start with :, { or $(. 
	if ($libs =~ /^\"?(?::|\{|\$\()/){
	    $self->{LDLOADLIBS} = $libs;
	    last;
	}
    }

    if ( !$self->{OBJECT} ) {
	# init_dirscan should have found out, if we have C files
	$self->{OBJECT} = "";
	$self->{OBJECT} = "$self->{BASEEXT}.c" if @{$self->{C}||[]};
    } else {
    	$self->{OBJECT} =~ s/\$\(O_FILES\)/@{$self->{C}||[]}/;
    }
    my($src);
    foreach (split(/[ \t\n]+/, $self->{OBJECT})) {
    	if (/^$self->{BASEEXT}\.o(bj)?$/) {
	    $src .= " $self->{BASEEXT}.c";
	} elsif (/^(.*\..*)\.o$/) {
	    $src .= " $1";
	} elsif (/^(.*)\.o(bj)?$/) {
	    if (-f "$1.cp") {
	    	$src .= " $1.cp";
	    } else {
	    	$src .= " $1.c";
	    }
	} else {
	    $src .= " $_";
	}
    }
    $self->{SOURCE} = $src;
}

=item file_name_is_absolute

Takes as argument a path and returns true, it it is an absolute path.

=cut

sub file_name_is_absolute {
    my($self,$file) = @_;
    $file =~ m/:/ ;
}

=item catdir

Concatenate two or more directory names to form a complete path ending
with a directory

=cut

# ';

sub catdir  {
    shift;
    my $result = shift;
    my $dir;
    $result = ":$result" unless ($result =~ /:/);
    foreach (@_) {
    	$result .= ":" unless ($result =~ /:$/);
	($dir = $_) =~ s/^://;
	$result .= $dir;
    }
    $result;
}

=item catfile

Concatenate two or more directory names and a filename to form a
complete path ending with a filename

=cut

sub catfile {
    &catdir;
}

=item path

Takes no argument, returns the environment variable PATH as an array.

=cut

sub path {
    my($self) = @_;
    my $path_sep = ",";
    my $path = $ENV{Commands};
    my @path = split $path_sep, $path;
}


=item init_dirscan

Initializes DIR, XS, PM, C, O_FILES, H, PL_FILES, MAN*PODS, EXE_FILES.

=cut

sub init_dirscan {	# --- File and Directory Lists (.xs .pm .pod etc)
    my($self) = @_;
    unless (ref $self){
	ExtUtils::MakeMaker::TieAtt::warndirectuse((caller(0))[3]);
	$self = $ExtUtils::MakeMaker::Parent[-1];
    }
    my($name, %dir, %xs, %c, %h, %ignore, %pl_files, %manifypods);
    local(%pm); #the sub in find() has to see this hash

    # in case we don't find it below!
    if ($self->{VERSION_FROM}) {
        my $version_from = macify($self->{VERSION_FROM});
        $pm{$version_from} = $self->catfile('$(INST_LIBDIR)',
            $version_from);
    }

    $ignore{'test.pl'} = 1;
    foreach $name ($self->lsdir(":")){
	next if ($name =~ /^\./ or $ignore{$name});
	next unless $self->libscan($name);
	if (-d $name){
	    $dir{$name} = $name if (-f ":$name:Makefile.PL");
	} elsif ($name =~ /\.xs$/){
	    my($c); ($c = $name) =~ s/\.xs$/.c/;
	    $xs{$name} = $c;
	    $c{$c} = 1;
	} elsif ($name =~ /\.c(p|pp|xx|c)?$/i){  # .c .C .cpp .cxx .cc .cp
	    $c{$name} = 1
		unless $name =~ m/perlmain\.c/; # See MAP_TARGET
	} elsif ($name =~ /\.h$/i){
	    $h{$name} = 1;
	} elsif ($name =~ /\.(p[ml]|pod)$/){
	    $pm{$name} = $self->catfile('$(INST_LIBDIR)',$name);
	} elsif ($name =~ /\.PL$/ && $name ne "Makefile.PL") {
	    ($pl_files{$name} = $name) =~ s/\.PL$// ;
	}
    }

    # Some larger extensions often wish to install a number of *.pm/pl
    # files into the library in various locations.

    # The attribute PMLIBDIRS holds an array reference which lists
    # subdirectories which we should search for library files to
    # install. PMLIBDIRS defaults to [ 'lib', $self->{BASEEXT} ].  We
    # recursively search through the named directories (skipping any
    # which don't exist or contain Makefile.PL files).

    # For each *.pm or *.pl file found $self->libscan() is called with
    # the default installation path in $_[1]. The return value of
    # libscan defines the actual installation location.  The default
    # libscan function simply returns the path.  The file is skipped
    # if libscan returns false.

    # The default installation location passed to libscan in $_[1] is:
    #
    #  ./*.pm		=> $(INST_LIBDIR)/*.pm
    #  ./xyz/...	=> $(INST_LIBDIR)/xyz/...
    #  ./lib/...	=> $(INST_LIB)/...
    #
    # In this way the 'lib' directory is seen as the root of the actual
    # perl library whereas the others are relative to INST_LIBDIR
    # (which includes ROOTEXT). This is a subtle distinction but one
    # that's important for nested modules.

    $self->{PMLIBDIRS} = ['lib', $self->{BASEEXT}]
	unless $self->{PMLIBDIRS};

    #only existing directories that aren't in $dir are allowed

    my (@pmlibdirs) = map { macify ($_) } @{$self->{PMLIBDIRS}};
    my ($pmlibdir);
    @{$self->{PMLIBDIRS}} = ();
    foreach $pmlibdir (@pmlibdirs) {
	-d $pmlibdir && !$dir{$pmlibdir} && push @{$self->{PMLIBDIRS}}, $pmlibdir;
    }

    if (@{$self->{PMLIBDIRS}}){
	print "Searching PMLIBDIRS: @{$self->{PMLIBDIRS}}\n"
	    if ($Verbose >= 2);
	require File::Find;
	File::Find::find(sub {
	    if (-d $_){
		if ($_ eq "CVS" || $_ eq "RCS"){
		    $File::Find::prune = 1;
		}
		return;
	    }
	    my($path, $prefix) = ($File::Find::name, '$(INST_LIBDIR)');
	    my($striplibpath,$striplibname);
	    $prefix =  '$(INST_LIB)' if (($striplibpath = $path) =~ s:^(\W*)lib\W:$1:);
	    ($striplibname,$striplibpath) = fileparse($striplibpath);
	    my($inst) = $self->catfile($prefix,$striplibpath,$striplibname);
	    local($_) = $inst; # for backwards compatibility
	    $inst = $self->libscan($inst);
	    print "libscan($path) => '$inst'\n" if ($Verbose >= 2);
	    return unless $inst;
	    $pm{$path} = $inst;
	}, @{$self->{PMLIBDIRS}});
    }

    $self->{DIR} = [sort keys %dir] unless $self->{DIR};
    $self->{XS}  = \%xs             unless $self->{XS};
    $self->{PM}  = \%pm             unless $self->{PM};
    $self->{C}   = [sort keys %c]   unless $self->{C};
    $self->{H}   = [sort keys %h]   unless $self->{H};
    $self->{PL_FILES} = \%pl_files unless $self->{PL_FILES};

    # Set up names of manual pages to generate from pods
    unless ($self->{MAN1PODS}) {
    	$self->{MAN1PODS} = {};
    }
    unless ($self->{MAN3PODS}) {
    	$self->{MAN3PODS} = {};
    }
}

=item libscan (o)

Takes a path to a file that is found by init_dirscan and returns false
if we don't want to include this file in the library. Mainly used to
exclude RCS, CVS, and SCCS directories from installation.

=cut

# ';

sub libscan {
    my($self,$path) = @_;
    return '' if $path =~ m/:(RCS|CVS|SCCS):/ ;
    $path;
}

=item constants (o)

Initializes lots of constants and .SUFFIXES and .PHONY

=cut

sub constants {
    my($self) = @_;
    unless (ref $self){
	ExtUtils::MakeMaker::TieAtt::warndirectuse((caller(0))[3]);
	$self = $ExtUtils::MakeMaker::Parent[-1];
    }
    my(@m,$tmp);

    for $tmp (qw/
	      NAME DISTNAME NAME_SYM VERSION VERSION_SYM XS_VERSION
	      INST_LIB INST_ARCHLIB PERL_LIB PERL_SRC PERL FULLPERL
	      XSPROTOARG LDLOADLIBS SOURCE TYPEMAPS
	      / ) {
	next unless defined $self->{$tmp};
	push @m, "$tmp = $self->{$tmp}\n";
    }

    push @m, q{
MODULES = }.join(" \\\n\t", sort keys %{$self->{PM}})."\n";
    push @m, "PMLIBDIRS = @{$self->{PMLIBDIRS}}\n" if @{$self->{PMLIBDIRS}};

    push @m, '

.INCLUDE : $(PERL_SRC)BuildRules.mk

';

    push @m, q{
# FULLEXT = Pathname for extension directory (eg DBD:Oracle).
# BASEEXT = Basename part of FULLEXT. May be just equal FULLEXT.
# ROOTEXT = Directory part of FULLEXT (eg DBD)
# DLBASE  = Basename part of dynamic library. May be just equal BASEEXT.
};

    if ($self->{DEFINE}) {
    	$self->{DEFINE} =~ s/-D/-d /g; # Preprocessor definitions may be useful
    	$self->{DEFINE} =~ s/-I\S+//g; # UN*X includes probably are not useful
    }
    if ($self->{INC}) {
    	$self->{INC} =~ s/-I\S+//g; # UN*X includes probably are not useful
    }
    for $tmp (qw/
	      FULLEXT BASEEXT ROOTEXT DEFINE INC
	      /	) {
	next unless defined $self->{$tmp};
	push @m, "$tmp = $self->{$tmp}\n";
    }

    push @m, "
# Handy lists of source code files:
XS_FILES= ".join(" \\\n\t", sort keys %{$self->{XS}})."
C_FILES = ".join(" \\\n\t", @{$self->{C}})."
H_FILES = ".join(" \\\n\t", @{$self->{H}})."
";

    push @m, '

.INCLUDE : $(PERL_SRC)ext:ExtBuildRules.mk
';

    join('',@m);
}

=item static (o)

Defines the static target.

=cut

sub static {
# --- Static Loading Sections ---

    my($self) = shift;
    unless (ref $self){
	ExtUtils::MakeMaker::TieAtt::warndirectuse((caller(0))[3]);
	$self = $ExtUtils::MakeMaker::Parent[-1];
    }
    my($extlib) = $self->{MYEXTLIB} ? "\nstatic :: myextlib\n" : "";
    '
all :: static

install :: do_install_static

install_static :: do_install_static
' . $extlib;
}

=item dlsyms (o)

Used by MacOS to define DL_FUNCS and DL_VARS and write the *.exp
files.

=cut

sub dlsyms {
    my($self,%attribs) = @_;
    unless (ref $self){
	ExtUtils::MakeMaker::TieAtt::warndirectuse((caller(0))[3]);
	$self = $ExtUtils::MakeMaker::Parent[-1];
    }

    return '' unless !$self->{SKIPHASH}{'dynamic'};

    my($funcs) = $attribs{DL_FUNCS} || $self->{DL_FUNCS} || {};
    my($vars)  = $attribs{DL_VARS} || $self->{DL_VARS} || [];
    my(@m);

    push(@m,"
dynamic :: $self->{BASEEXT}.exp

") unless $self->{SKIPHASH}{'dynamic'};

    my($extlib) = $self->{MYEXTLIB} ? " myextlib" : "";

    push(@m,"
$self->{BASEEXT}.exp: Makefile.PL$extlib
",'	$(PERL) "-I$(PERL_LIB)" -e \'use ExtUtils::Mksymlists; ',
        'Mksymlists("NAME" => "',$self->{NAME},'", "DL_FUNCS" => ',
	neatvalue($funcs),', "DL_VARS" => ', neatvalue($vars), ');\'
');

    join('',@m);
}

=item dynamic (o)

Defines the dynamic target.

=cut

sub dynamic {
# --- dynamic Loading Sections ---

    my($self) = shift;
    unless (ref $self){
	ExtUtils::MakeMaker::TieAtt::warndirectuse((caller(0))[3]);
	$self = $ExtUtils::MakeMaker::Parent[-1];
    }
    '
all :: dynamic

install :: do_install_dynamic

install_dynamic :: do_install_dynamic
';
}


=item clean (o)

Defines the clean target.

=cut

sub clean {
# --- Cleanup and Distribution Sections ---

    my($self, %attribs) = @_;
    unless (ref $self){
	ExtUtils::MakeMaker::TieAtt::warndirectuse((caller(0))[3]);
	$self = $ExtUtils::MakeMaker::Parent[-1];
    }
    my(@m,$dir);
    push(@m, '
# Delete temporary files but do not touch installed files. We don\'t delete
# the Makefile here so a later make realclean still has a makefile to use.

clean ::
');
    # clean subdirectories first
    for $dir (@{$self->{DIR}}) {
	push @m, 
"	Set OldEcho \{Echo\}
	Set Echo 0
	Directory $dir
	If \"\`Exists -f $self->{MAKEFILE}\`\" != \"\"
	    \$(MAKE) clean
	End
	Set Echo \{OldEcho\}
	";
    }

    my(@otherfiles) = values %{$self->{XS}}; # .c files from *.xs files
    push(@otherfiles, patternify($attribs{FILES})) if $attribs{FILES};
    push @m, "\t\$(RM_RF) @otherfiles\n";
    # See realclean and ext/utils/make_ext for usage of Makefile.old
    push(@m,
	 "\t\$(MV) $self->{MAKEFILE} $self->{MAKEFILE}.old\n");
    push(@m,
	 "\t$attribs{POSTOP}\n")   if $attribs{POSTOP};
    join("", @m);
}

=item realclean (o)

Defines the realclean target.

=cut

sub realclean {
    my($self, %attribs) = @_;
    unless (ref $self){
	ExtUtils::MakeMaker::TieAtt::warndirectuse((caller(0))[3]);
	$self = $ExtUtils::MakeMaker::Parent[-1];
    }
    my(@m);
    push(@m,'
# Delete temporary files (via clean) and also delete installed files
realclean purge ::  clean
');
    # realclean subdirectories first (already cleaned)
    my $sub = 
"	Set OldEcho \{Echo\}
	Set Echo 0
	Directory %s
	If \"\`Exists -f %s\`\" != \"\"
	    \$(MAKE) realclean
	End
	Set Echo \{OldEcho\}
	";
    foreach(@{$self->{DIR}}){
	push(@m, sprintf($sub,$_,"$self->{MAKEFILE}.old","-f $self->{MAKEFILE}.old"));
	push(@m, sprintf($sub,$_,"$self->{MAKEFILE}",''));
    }
    my(@otherfiles) = ($self->{MAKEFILE},
		       "$self->{MAKEFILE}.old"); # Makefiles last
    push(@otherfiles, patternify($attribs{FILES})) if $attribs{FILES};
    push(@m, "	\$(RM_RF) @otherfiles\n") if @otherfiles;
    push(@m, "	$attribs{POSTOP}\n")       if $attribs{POSTOP};
    join("", @m);
}

=item rulez (o)

=cut

sub rulez {
    my($self) = shift;
    unless (ref $self){
	ExtUtils::MakeMaker::TieAtt::warndirectuse((caller(0))[3]);
	$self = $ExtUtils::MakeMaker::Parent[-1];
    }
    qq'
install install_static install_dynamic :: 
	\$(PERL_SRC)PerlInstall -l \$(PERL_LIB)
	\$(PERL_SRC)PerlInstall -l "$ENV{MACPERL}site_perl:"

.INCLUDE : \$(PERL_SRC)BulkBuildRules.mk
';
}

sub xsubpp_version
{
    return $ExtUtils::MakeMaker::Version;
}

#=======================================
# stuff added by pudge, 12 January, 1998
#=======================================
use AutoSplit;
use File::Copy;
use File::Find;
use File::Path;
use Mac::Files;
use Mac::MoreFiles qw(%Application);

sub make {
    my($self, $make_data, $name, $prefix, %copy, $file, @files, %mkpath, $cwd);
    $self = shift;
    $self->{'make'} = 'YES';
    $cwd = cwd();

    undef $@;
    unless (eval { do ":Makefile.PL" }) {
        warn "Can't do :Makefile.PL in $cwd\n";
    }
    warn $@ if $@;

    $make_data = $ExtUtils::MM_MacOS::make_data{$cwd}
        or die "No $cwd package data";

    @files = ((sort keys %{$make_data->{PM}}),
        (sort keys %{$make_data->{XS}}));
    
    # taken from InstallBLIB
    $name = $make_data->{NAME};
    if (($prefix) = $name =~ /(.*::)/) {
	    $prefix =~ s/::/:/g;
    }

    FILE:
    for $file (@files) {
	    $file = ":$file" unless $file =~ /^:/;

#       this doesn't seem to be right: if something is in :lib:,
#       should we assume it already has the right prefxies?
#       (my $new = $file) =~ s|^:(lib:)?|:blib:lib:$prefix|;
        (my $new = $file) =~ s/^:(lib:|$prefix)?/':blib:lib:' .
            ($1 eq 'lib:' ? '' : $prefix)/e;

        XSCHECK: {
	    	if ($file =~ /\.xs$/) {
	    		open(F, $file) || die;
	    		while (<F>) {
	    			last XSCHECK if /^=/; 
	    		}
	    		print STDERR "Skipping $file, which doesn't contain any pod.\n";
	    		next FILE;
	    	}
	    }
        $copy{$file} = $new;
	    $new =~ /^(.*:)/; 
	    $mkpath{$1} = 1;
    }
    mkpath([sort keys %mkpath], 1);

    foreach my $file (keys %copy) {
        print "copying $file -> $copy{$file}\n";
        copy($file, $copy{$file});
    }
}

sub make_test {
    my $self = shift;
    $self->{'make_test'} = 'YES';
}

sub make_clean {}

sub make_install {
    # taken from PerlInstall
    my(%dirs, $dir, $d);
    $dirs{lib} = "$ENV{MACPERL}site_perl";
	chomp($dir = `pwd`);

	$dir .= ":" unless ($dir =~ /:$/);
	$dir .= "blib";

    my($fromdir, $todir);
    my $make_copyit = sub {
	    local($_) = $_;
	    my($newdir,$auto,$name) = ($File::Find::dir,
	        $File::Find::dir, $File::Find::name);
	    $newdir =~ s/\Q$fromdir\E/$todir/;
	    $auto   =~ s/.*\Q$fromdir\E.*$/$todir:auto/;
	    $name   =~ s/.*\Q$fromdir\E//;
	    return if -d $_;
	    $newdir =~ s/:$//;
	    printf("    %-20s -> %s\n", $name, $newdir);
	    mkpath($newdir, 1);
	    if (!copy($_, "$newdir:$_")) {
	        die $^E unless -e "$newdir:$_";
    	    printf("    Moving %-20s -> %s\nDelete old file manually\n",
    	        "$newdir:$_", "$newdir:$_ old");
	        move "$newdir:$_", "$newdir:$_ old";
	        copy($_, "$newdir:$_") or die $^E;
	    }
	    autosplit("$newdir:$_", $auto, 0, 1, 0) if /\.pm$/;
    };

	opendir(DIR, $dir);
	while (defined($d = readdir(DIR))) {
		next unless -d "$dir:$d";
		$fromdir = "$dir:$d";
		$todir   = $dirs{$d};
		print "  $fromdir\n";
		find($make_copyit, $fromdir);
	}
	closedir(DIR);

    $self->{'make_install'} = 'YES';
}


sub convert_files {
    require Mac::Conversions;
    my($files, $verbose) = @_;
    my $conv = Mac::Conversions->new(Remove => 1);
    foreach my $file (@$files) {
        $file = ':' . Archive::Tar::_munge_file($file);
        chmod 0666, $file or die "$file: $!";
        if (-T $file) {
            chmod 0666, $file or die $!;
            local(*FILE, $/);
            open(FILE, "< $file\0") or die $!;
            my $text = <FILE>;
            next unless $text;
            $text =~ s/\015?\012/\n/g;
            close(FILE);
            open(FILE, "> $file\0") or die $!;
            print FILE $text;
            close(FILE);
            print "LF->CR translate  $file\n" if $verbose;
        } elsif (-B $file && $file =~ /\.bin$/) {
            $conv->demacbinary($file);
            print "convert MacBinary $file\n" if $verbose;
        } elsif (-f _) {
            print "left alone        $file\n" if $verbose;
        }
    }
}

sub launch_file {
    require Mac::AppleEvents::Simple;
    Mac::AppleEvents::Simple->import;
    my($file, $use_cwd, $wait) = @_;
    my($editor, @editors);

    $wait ||= 0;
    if ($use_cwd) {
        chomp(my $cwd = `pwd`);
        $file =~ s/^://;
        $file = "$cwd:$file";
    }

    @editors = qw(R*ch ALFA ttxt);  #  others?
    unshift @editors, $ENV{EDITOR} if $ENV{EDITOR};
    unshift @editors, $CPAN::Config->{pager}
        if $CPAN::Config->{pager} && length ($CPAN::Config->{pager}) == 4;
    foreach (@editors) {
        $editor = $Application{$_};
        last if $editor;
    }

    do_event(qw/aevt odoc MACS/,
        q"'----':alis(@@), usin:alis(@@)",
        map {NewAliasMinimal $_} $file, $editor);
}

sub look {
    require Mac::AppleEvents::Simple;
    Mac::AppleEvents::Simple->import;
    my($self, $cwd) = @_;
    $cwd = $self->dir or $self->get;
    $cwd = $self->dir;
    do_event(qw/aevt odoc MACS/,
        q"'----':alis(@@)",
        NewAliasMinimal($cwd));
}

1;

__END__
