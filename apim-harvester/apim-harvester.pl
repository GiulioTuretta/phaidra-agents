#!/usr/bin/perl -w

=head1 NAME

apim-harvester.pl


=head1 DESCRIPTION

This is glue code that takes data from activemq [Apache messaging bus]
and writes it to MongoDB Because of the current limitation in fedora-commons, 
it only has api-m records at the moment.

=cut

use Net::Stomp;
use XML::XML2JSON;
use JSON::XS;
use YAML::Syck;
use MongoDB;
use Data::Dumper;
use Log::Log4perl;

my $config = YAML::Syck::LoadFile('/etc/phaidra.yml');
Log::Log4perl->init_once("/etc/phaidra_logging.conf");

=head2 configuration, put onto the end of phaidra.yml
apimharvester:
   stomp_host: 'localhost.localdomain'
   stomp_port: 61613
   stomp_user: 'not used at present'
   stomp_password: 'not used at present'
   mongo_host: 'host'
   mongo_user: 'user'
   mongo_password: 'secret'
   mongo_port: 27017 # not needed, if standard 27017
   mongo_db:  'db'
   mongo_collection: 'apim'
   update_topic: 'fedora.apim.update'
   access_topic: 'fedora.apim.access'
=cut

# format is: my $client = MongoDB::MongoClient->new( "host" =>
#      "mongodb://username:pass\@host\/db" );
# one in the doc, doesn't seem to work?

my $log = Log::Log4perl->get_logger("Phaidra::Apimharvester");

=cut
my $uri = "mongodb://".$config->{apimharvester}->{mongo_user}.":".$config->{apimharvester}->{mongo_password}."@". $config->{apimharvester}->{mongo_host}."/".$config->{apimharvester}->{mongo_db};
my $client = MongoDB->connect($uri);
=cut

=cut
  MongoDB::MongoClient->new( "host" =>
"mongodb://$config->{'apimharvester'}->{'mongo_user'}:$config->{'apimharvester'}->{'mongo_password'}\@$config->{'apimharvester'}->{'mongo_host'}\/$config->{'apimharvester'}->{'mongo_db'}"
  );
=cut

my $client = MongoDB::Connection->new(
  host => $config->{apimharvester}->{mongo_host}, 
  port => "27017",
  username => $config->{apimharvester}->{mongo_user},
  password => $config->{apimharvester}->{mongo_password},
  db_name => $config->{apimharvester}->{mongo_db}
);

my $db = $client->get_database( $config->{'apimharvester'}->{'mongo_db'} );
my $messages =
  $db->get_collection( $config->{'apimharvester'}->{'mongo_collection'} );

# store the frame bodies here for debugging before trying to put into Mongo
my $debug_file = 'debug.txt';
open my $fh, '>>', $debug_file;

# set up connection to activemq on default port for non-ssl stomp
my $stomp = Net::Stomp->new(
    {
        hostname => $config->{'apimharvester'}->{'stomp_host'},
        port     => $config->{'apimharvester'}->{'stomp_port'}
    }
);
$stomp->connect();

# this will create the topics, as described in: https://wiki.duraspace.org/display/FEDORA34/Messaging
# if they are not already created

my $return_code;
$return_code = $stomp->subscribe(
    {
        'destination' => "/topic/$config->{'apimharvester'}->{'update_topic'}",
        'ack'         => 'client',
    }
);
$return_code = $stomp->subscribe(
    {
        'destination' => "/topic/$config->{'apimharvester'}->{'access_topic'}",
        'ack'         => 'client',
    }
);

# receive frame, will block until there is a frame
while (1) {

    my $frame = $stomp->receive_frame;

    my $converter = XML::XML2JSON->new( 'force_array' => 1 );
    my $json = $converter->convert( $frame->body );
    my $decoded = JSON::XS::decode_json($json);    
    $log->debug( $frame->body );
    my $id = $messages->insert( { 'data' => $decoded } );
    my $x = Dumper $json;
    $log->debug( "mongo id is:" . $id . " json is:" . $x );
    $stomp->ack( { frame => $frame } );

}

$stomp->disconnect;
exit 0;
