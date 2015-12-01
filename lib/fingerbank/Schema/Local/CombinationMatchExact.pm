package fingerbank::Schema::Local::CombinationMatchExact;

use Moose;
use namespace::autoclean;

extends 'fingerbank::Base::Schema::CombinationMatchExact';

# special case, we have wilcards when the column is empty
# this view handles it

# $1 = dhcp_fingerprint
# $2 = dhcp_vendor
# $3 = user_agent
# $4 = mac_vendor
# $5 = dhcp6_fingerprint
# $6 = dhcp6_enterprise
__PACKAGE__->result_source_instance->view_definition(q{
    SELECT * FROM combination
    WHERE (dhcp_fingerprint_id = $1 OR dhcp_fingerprint_id='')
        AND (dhcp_vendor_id = $2 OR dhcp_vendor_id='')
        AND (user_agent_id = $3 OR user_agent_id='')
        AND ((mac_vendor_id = $4 OR mac_vendor_id IS NULL) or mac_vendor_id='')
        AND (dhcp6_fingerprint_id = $5 OR dhcp6_fingerprint_id='')
        AND (dhcp6_enterprise_id = $6 OR dhcp6_enterprise_id='')
    ORDER BY
    score DESC LIMIT 1
});

__PACKAGE__->meta->make_immutable;

1;
