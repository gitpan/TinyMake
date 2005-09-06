package TinyMake;
$TinyMake::VERSION = '0.02';

=head1 NAME

TinyMake - A minimalist build language, similar in purpose to make and ant.

=head1 SYNOPSIS

   use TinyMake ':all';

   synonym all => ['codeGen', 'compile', 'dataLoad', 'test'];

   file { # generate code here
     `touch $target`; 
   } codeGen => 'database.spec';

   file { # compile code here
     `touch $target`;
   } compile => 'codeGen';

   file { # load data here
	  `touch $target`;
   } dataLoad => 'codeGen';

   file { # test code here
     `touch $target`;
   } test => ['compile', 'dataLoad'];

   file { `rm compile codeGen dataLoad test` } clean => [];

   make @ARGV

=cut

use strict;
require Exporter;
our @ISA = ("Exporter");
our @EXPORT_OK = qw(file synonym make tree group $target @changed %extra);
our %EXPORT_TAGS = (
						  all => \@EXPORT_OK,
						  simple => [qw(file synonym make)]
						 );
our @changed = ();
our $target = undef;
our %extra = ();

our @tasks = ();

sub file(&@) {
  my ($rule,$target,$sources,%extra) = @_;
  $sources = [$sources] if (ref $sources eq '');
  my $file = synonym ($target , $sources);
  $file->{rule} = $rule;
  $file->{extra} = {%extra};
  return $file;
}
sub synonym(@) {
  my ($target,$sources) = @_;
  $sources = [$sources] if (ref $sources eq '');
  my $synonym = {target=>$target, sources=>$sources};
  push @tasks,$synonym;
  return $synonym;
}
sub group(&@){
  my ($coderef, $synonym, $href,%extra) = @_;
  my @targets = keys %$href;
  foreach my $target (@targets){
	 my $source = $href->{$target};
	 my $file = synonym($target,$source);
	 $file->{rule} = $coderef;
	 $file->{extra} = {%extra};
  }
  synonym($synonym, [@targets]);
  return keys %$href;
}

sub depgraph {
  my ($tn,$result,$visited) = @_;

  die "TinyMake does not support circular dependency '$tn'\n" 
	 if (grep {defined $_ && $tn eq $_} @$visited);

  my ($t) = grep {$_->{target} eq $tn} @tasks;
  unless ($t == undef){
	 push @$visited, $tn;

	 foreach my $source (@{$t->{sources}}){
		
		depgraph($source,$result,$visited) ;
		# 
		# pop the source off the visited stack
		#
		map { $_ = $_ eq $source?undef:$_ } @$visited;
		
	 }
	 push (@$result, $t) unless grep {$_->{target} eq $t->{target}} @$result;
  }
  return @$result;
}
sub make(@) {
  my (@tnames) = @_;
  my @result = ();
  @tnames = ($tasks[0]->{target}) unless (@tnames);
  foreach (@tnames){
	 my $rebuilt = 0;
	 my @descendants = ();
	 my @orderedTasksWithRules = grep {defined $_->{rule}} depgraph($_,[],[]);
	 foreach my $task (@orderedTasksWithRules) {
		$target = $task->{target};
		@changed = ();
		my $exec = 0;
		if (-e $target){
		  @changed = grep { -M $target > -M && -e} @{$task->{sources}};
		}else{
		  $exec = 1;
		  @changed = @{$task->{sources}};
		}
		if ($exec or @changed) {
		  %extra = exists $task->{extra}?%{$task->{extra}}:();
		  push @result, $target;
		  $task->{rule}->();
		  $rebuilt = 1;
		}
	 }
	 print "'$_' is up to date\n" unless $rebuilt;
  }
  return @result;
}

use File::Find ;
sub tree {
  my @found = ();
  File::Find::find sub{	 push @found, $File::Find::name }, @_;
  return @found;
}

1;

__END__


=head1 DESCRIPTION

This Perl Module allows you to define file-based dependencies similar to how make works.
Rather than placing the build rules in a separate Makefile or build.xml, the build rules
are declared using standard Perl syntax. TinyMake is effectively an inline domain-specific language.
Using make you might write a makefile that looks like this...

 test: compile dataLoad
   # test
   touch test

 codeGen: database.spec
	# generate code
	touch codeGen

 compile: codeGen
	# compile code 
	touch compile

 dataLoad: codeGen
	# load data
	touch dataLoad

 database.spec: # source file

The equivalent perl code using TinyMake would look like this...

 use TinyMake ':all';

 # some perl code
 .
 . 
 .
 file { # test
   `touch test`;
 } test => ['compile','dataLoad'];

 file {  # generate code
   `touch codeGen`;
 } codeGen => 'database.spec';
  
 # some more perl code
 .
 . 
 .
 file { # compile code
   `touch compile`;
 } compile => 'codeGen';

 file { # load data
   `touch dataLoad`;
 } dataload => 'codeGen';

 make @ARGV;

Using TinyMake you declare a file dependency using the C<file { ... }>  subroutine.
This subroutine accepts a bare block of code as its first parameter, a filename (the target) 
and a list of prerequisites as its 2nd and 3rd parameters. The code block passed in as the
1st parameter will only be executed if the target file is out of date. A target file is
considered to be out of date if ...

=over 4

=item 1.

the target file doesn't exist or...

=item 2.

any of the prerequisite files have been modified more recently than the target.

=back

TinyMake (as its name implies) is lacking in features, there are no implicit rules.
TinyMake doesn't know about C or any other language. All rules must be declared explicitly.
TinyMake provides the following subroutines...

=over 4

=item B<file>

   file { ... } $target => \@prerequisites;

The C<file> subroutine is used to declare a target, its prerequisites and a rule to invoke if the
target file is out of date. The code inside the C<{ ... }> curly braces does not get executed 
immediately. It will only be executed if the target is out of date. Typical usage would be...

 file {
        `xslfm -xsl index.xsl -files bookmarks.txt site.xml > index.html`;
 } 'index.html' => ['bookmarks.txt', 'site.xml'];

In the above example, C<index.html> is the target and both C<bookmarks.txt> and C<site.xml> are
prerequisites. If any of these two files change then C<index.html> should be rebuilt. The rule
to rebuild C<index.html> is the anonymous block of code supplied within the C<{ ... }> curly braces.
If you are familiar with Perl's sort routine and its syntax ...
 
   sort { $a <=> $b } @files;

... then you will have guessed that the initial block of code supplied to the C<file> method is not
executed immediately. Its execution is deferred until later when C<TinyMake> has determined whether any
prerequisite file have changed.

Just like Perl's native C<sort> subroutine, TinyMake exports some global variables which have special meaning 
within the scope of the rule block. These special variables are...

=over

=item B<$target> 

This is the target filename. This is equivalent to make's automatic variable C<$@>.

=item B<@changed> 

This is the list of prerequisite files which are newer than the target. This may not necessarily be all of the 
prerequisites supplied - only those which have changed since the target file was last modified. This is 
equivalent to make's automatic variable C<$?>.

=item B<%extra>

This is a hash of additional information supplied to the rule at declaration time. e.g.

   file {
     `javac -d $extra{d} -classpath $extra{classpath} $changed[0]`
   } '../classes/Sample.class' => ['Sample.java'],
     d => '../classes',
     classpath => '../libs';

Any additional parameters which are passed to C<file> after the prerequisites are stored in the 
special variable %extra for use by the rule when it is executed.

=back

Prerequisites must be enclosed in C<[ ... ]> square brackets. If there is only one prerequisite then
no square brackets are required. E.g. The example above can be rewritten as...

   file {
     `javac -d $extra{d} -classpath $extra{classpath} $changed[0]`
   } '../classes/Sample.class' => 'Sample.java',
     d => '../classes',
     classpath => '../libs';

To create Ant-style tasks simply don't bother updating or touching the target file. 
No file modification dates are checked so the task will be executed if it is in the dependency tree for the active target.
The C<@changed> variable will contain all of the task's prerequisites, not just those that are newer than
the target. The following sample code illustrates how to make breakfast using TinyMake ...

  use TinyMake ':all';
  use strict;
  file { print "BURP!\n"                   } breakfast => ["prepare","fry","serve"];
  file { print "Adding pepper...\n"        } add_pepper => "fetch_bowl";
  file { print "Breakfast is served !\n"   } serve => "fry";
  file { print "Breaking eggs...\n"        } break_eggs => "fetch_bowl";
  file { print "Fetching bowl...\n"        } fetch_bowl => undef;
  file { print "Frying omelette...\n"      } fry => "prepare";
  file { print "Omelette is prepared...\n" } prepare => ["break_eggs","add_pepper","whisk"];
  file { print "Whisking ...\n"            } whisk => ["add_pepper", "break_eggs"];
  
  make @ARGV;

In the above example, a call to C<make 'breakfast'>, will result in the following output...

  Fetching bowl...
  Breaking eggs...
  Adding pepper...
  Whisking ...
  Omelette is prepared...
  Frying omelette...
  Breakfast is served !
  BURP!

Note that each task is executed only once even though it may be a prerequisite for many other tasks.
Note that the sequence in which each task is defined has no bearing whatsoever on the sequence in which
they are executed.


=item B<synonym>

    synonym $symbolicTarget => \@prerequisites

A synonym is a special type of target in that it has no rule associated with it.
Synonyms provide a handy way of creating a short alias for long and difficult-to-remember filenames.
A synonym can be created for either a single target or multiple targets. If you are using TinyMake
extensively you will probably create a synonym like the following...

 synonym all => ['generate', 'compile', 'install' ];

As with the C<file> subroutine, the C<[ ]> square brackets are optional if there is only one prerequisite.

 synonym password => '/etc/conf/hercules/realms/database/simpleQL/passwd';

...is the same as...

 synonym password => ['/etc/conf/hercules/realms/database/simpleQL/passwd'];



=item B<make>
  
  make @targets

The C<make> subroutine kicks off the build process. make takes 1 or more filenames/targets as its parameters
and determines ...

=over

=item 1. 

The order in which the target and its prerequisites should be built.

=item 2.

Which (if any) prerequisites are out of date and must be built.

=back 

If no arguments are supplied to C<make> then (like make and Ant) it assumes the first target that was defined using C<file> 
is the target to check. For this reason you should create an 'all' file/synonym at the start of your perl script.
make returns a list of changed targets.

=item B<tree>

  tree @dirs

This is a helper function which returns a list of all of the files in the specified directory and subdirectories.

=item B<group>

 group { rule code } $symbolicTarget => \%target_source_map

Imagine a scenario in which you have a directory with a number of B<.txt> files in it. Each of the B<.txt>
files must be converted to corresponding B<.html> files. Using standard makefile syntax you would do 
something like this...

   .SUFFIXES: .txt .html
  
   .txt.html:
       ${HTML_COMPILER} $< > $@

Using TinyMake there are 2 ways to do this. The first is to create a hash of html-to-txt files. This could
be done as follows...

   my %html2txt = map {/(.*)txt$/; "$1html" => $_ } glob "*.txt";

The next step would be to call C<file> for each key/value combination as follows...

   foreach (keys %html2txt){
     file {
       # convert all .txt files to .html files
       `cp $changed[0] $target`;
     } $_ => $txt2html{$_}
   } 

Once we've create a file target for each html file with a corresponding .txt file as the prerequisite, we 
would probably want to create a catchall target under which to group all of the html files...
 
 synonym html [keys %html2txt];

We can now build all of the html files by calling C<make 'html';>. 
Since this kind of construct is pretty common there is a shorthand way to do this...

   group {
     # convert .txt file to .html
     `cp $changed[0] $target`;
   } html => {map {/(.*)txt$/; "$1html" => $_} glob "*.txt"};

What this effectively does is create multiple file targets for each .html file and create a synonym called
'html'. Remember - the rule block for a group applies to each key/value pair in the supplied hash reference, not the
group name which is really just a synonym. The rule block above will never be called with 'html' as the
target. Instead it will be called for each key/value combination where key is the target and value is the
the prerequisite/s. 

=head1 SAMPLE CODE

The following code is a sample perl script that uses TinyMake to compile a tree of java source code
and construct a C<.JAR> archive file from the built tree.

   use strict;
   use TinyMake ':all';
   
   my $sourcepath  = "./java";
   my $classpath   = "../lib/classes";
   my $outputpath  = "../bin";
   my $project_jar = "$outputpath/project.jar";
   #
   # build full jar by default
   #
   synonym default => $project_jar;
   #
   # create a map of .class to .java files
   #
   my %dotClassDotJavaMap =  map {
     /$sourcepath(.*)java$/; 
     "$outputpath$1class" => $_ 
   } grep /\.java$/, tree $sourcepath;
   #
   # group the class-to-java map under the
   # 'compile' synonym
   #
   group { 
     `javac -d $extra{d} -classpath $extra{classpath} $changed[0]` 
   } compile => \%dotClassDotJavaMap,
     d => $outputpath,
     classpath => $classpath;
   
   #
   # rebuild the jar if any of the .class files change
   #
   file {
     `jar -cvf $target -C $extra{d} com`;
   } $project_jar => [keys %dotClassDotJavaMap],
     d => $outputpath;
   #
   # clean build
   #
   file { 
     `rm -R $outputpath/com`;
     `rm $project_jar`; 
   } clean => [];
     
   make @ARGV;

=head1 AUTHOR

Walter Higgins   walterh@rocketmail.com

=head1 BUGS

'file' prerequisites must be filenames, you should not use a synonym as a prerequisite to a 'file'.
e.g. 

   # WRONG !!!
   synonym compile => ['project.html', 'project.exe'];
   file { ... } 'project.tgz' => 'compile';

This is incorrect because TinyMake assumes that all prerequisites are files.
The correct way to do it is like this...

   # CORRECT 
   my $compile = ['project.html', 'project.exe'];
   synonym compile => $compile;
   file { ... } 'project.tgz' => $compile;

Please also refer to the java compilation example above.

=head1 SEE ALSO

http://martinfowler.com/articles/rake.html

=cut 
