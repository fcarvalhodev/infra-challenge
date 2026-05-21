package test

import (
	"context"
	"fmt"
	"net"
	"testing"

	"github.com/Azure/azure-sdk-for-go/sdk/azidentity"
	"github.com/Azure/azure-sdk-for-go/sdk/resourcemanager/authorization/armauthorization/v2"
	"github.com/Azure/azure-sdk-for-go/sdk/resourcemanager/network/armnetwork/v5"
	"github.com/Azure/azure-sdk-for-go/sdk/resourcemanager/storage/armstorage"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

const (
	subscriptionID    = "128100a8-3b59-40af-882c-7c6c91a676a2"
	resourceGroupName = "rg-devtest-lab-interviews"
	vmMIPrincipalID   = "fc77b65c-f439-44d6-b674-9beb9a5ca81a"
	environment       = "dev"
)

func newCredential(t *testing.T) *azidentity.DefaultAzureCredential {
	t.Helper()
	cred, err := azidentity.NewDefaultAzureCredential(nil)
	require.NoError(t, err, "failed to create Azure credential")
	return cred
}

// ---------------------------------------------------------------------------
// Test: VNet peering is Active in both directions
// ---------------------------------------------------------------------------
func TestVNetPeeringActive(t *testing.T) {
	t.Parallel()
	ctx := context.Background()
	cred := newCredential(t)

	client, err := armnetwork.NewVirtualNetworkPeeringsClient(subscriptionID, cred, nil)
	require.NoError(t, err)

	vnetBName := fmt.Sprintf("vnet-b-fabio-%s", environment)

	// Peering A -> B (lives on vnet-lab-interviews)
	peerAtoB, err := client.Get(ctx, resourceGroupName, "vnet-lab-interviews",
		fmt.Sprintf("peer-vneta-to-vnetb-%s", environment), nil)
	require.NoError(t, err, "peering A->B not found")
	assert.Equal(t, armnetwork.VirtualNetworkPeeringStateConnected,
		*peerAtoB.Properties.PeeringState, "peering A->B must be Connected")

	// Peering B -> A (lives on vnet-b-fabio-dev)
	peerBtoA, err := client.Get(ctx, resourceGroupName, vnetBName,
		fmt.Sprintf("peer-vnetb-to-vneta-%s", environment), nil)
	require.NoError(t, err, "peering B->A not found")
	assert.Equal(t, armnetwork.VirtualNetworkPeeringStateConnected,
		*peerBtoA.Properties.PeeringState, "peering B->A must be Connected")
}

// ---------------------------------------------------------------------------
// Test: Every candidate subnet has an NSG; no 0.0.0.0/0 inbound rule
// ---------------------------------------------------------------------------
func TestSubnetsHaveNSGAndNoPublicInbound(t *testing.T) {
	t.Parallel()
	ctx := context.Background()
	cred := newCredential(t)

	subnetClient, err := armnetwork.NewSubnetsClient(subscriptionID, cred, nil)
	require.NoError(t, err)

	vnetBName := fmt.Sprintf("vnet-b-fabio-%s", environment)

	pager := subnetClient.NewListPager(resourceGroupName, vnetBName, nil)
	for pager.More() {
		page, err := pager.NextPage(ctx)
		require.NoError(t, err)
		for _, subnet := range page.Value {
			t.Run(fmt.Sprintf("subnet-%s", *subnet.Name), func(t *testing.T) {
				assert.NotNil(t, subnet.Properties.NetworkSecurityGroup,
					"subnet %s must have an NSG attached", *subnet.Name)

				if subnet.Properties.NetworkSecurityGroup == nil {
					return
				}

				// Extract NSG name from resource ID and check rules
				nsgClient, err := armnetwork.NewSecurityGroupsClient(subscriptionID, cred, nil)
				require.NoError(t, err)

				nsgID := *subnet.Properties.NetworkSecurityGroup.ID
				nsgName := extractResourceName(nsgID)

				nsg, err := nsgClient.Get(ctx, resourceGroupName, nsgName, nil)
				require.NoError(t, err)

				for _, rule := range nsg.Properties.SecurityRules {
					if *rule.Properties.Direction == armnetwork.SecurityRuleDirectionInbound &&
						*rule.Properties.Access == armnetwork.SecurityRuleAccessAllow {
						src := ""
						if rule.Properties.SourceAddressPrefix != nil {
							src = *rule.Properties.SourceAddressPrefix
						}
						assert.NotEqual(t, "0.0.0.0/0", src,
							"NSG %s has an Allow-All inbound rule (0.0.0.0/0) on rule %s",
							nsgName, *rule.Name)
						assert.NotEqual(t, "*", src,
							"NSG %s has an Allow-* inbound rule on rule %s",
							nsgName, *rule.Name)
					}
				}
			})
		}
	}
}

// ---------------------------------------------------------------------------
// Test: Storage account FQDN resolves to a private IP
// ---------------------------------------------------------------------------
func TestStorageResolvesToPrivateIP(t *testing.T) {
	t.Parallel()
	ctx := context.Background()
	cred := newCredential(t)

	// Find the storage account by tag
	storageClient, err := armstorage.NewAccountsClient(subscriptionID, cred, nil)
	require.NoError(t, err)

	var storageAccountName string
	pager := storageClient.NewListByResourceGroupPager(resourceGroupName, nil)
	for pager.More() {
		page, err := pager.NextPage(ctx)
		require.NoError(t, err)
		for _, acc := range page.Value {
			tags := acc.Tags
			if owner, ok := tags["Owner"]; ok && *owner == "fabio" {
				if env, ok := tags["Environment"]; ok && *env == environment {
					storageAccountName = *acc.Name
					break
				}
			}
		}
	}
	require.NotEmpty(t, storageAccountName, "candidate storage account not found")

	fqdn := fmt.Sprintf("%s.blob.core.windows.net", storageAccountName)
	addrs, err := net.LookupHost(fqdn)
	require.NoError(t, err, "DNS lookup for %s failed", fqdn)
	require.NotEmpty(t, addrs)

	// All resolved IPs must be in a private range
	for _, addr := range addrs {
		ip := net.ParseIP(addr)
		require.NotNil(t, ip)
		assert.True(t, isPrivateIP(ip),
			"storage FQDN %s resolved to public IP %s — private endpoint not working", fqdn, addr)
	}
}

// ---------------------------------------------------------------------------
// Test: Storage public network access is disabled
// ---------------------------------------------------------------------------
func TestStoragePublicAccessDisabled(t *testing.T) {
	t.Parallel()
	ctx := context.Background()
	cred := newCredential(t)

	storageClient, err := armstorage.NewAccountsClient(subscriptionID, cred, nil)
	require.NoError(t, err)

	pager := storageClient.NewListByResourceGroupPager(resourceGroupName, nil)
	found := false
	for pager.More() {
		page, err := pager.NextPage(ctx)
		require.NoError(t, err)
		for _, acc := range page.Value {
			tags := acc.Tags
			if owner, ok := tags["Owner"]; !ok || *owner != "fabio" {
				continue
			}
			if env, ok := tags["Environment"]; !ok || *env != environment {
				continue
			}
			found = true
			assert.Equal(t, armstorage.PublicNetworkAccessDisabled,
				*acc.Properties.PublicNetworkAccess,
				"storage account %s must have public network access disabled", *acc.Name)
		}
	}
	assert.True(t, found, "no candidate storage account found with Owner=fabio, Environment=%s", environment)
}

// ---------------------------------------------------------------------------
// Test: vm-mi has exactly the three required runtime role assignments
// ---------------------------------------------------------------------------
func TestVMMIHasExactlyThreeRoleAssignments(t *testing.T) {
	t.Parallel()
	ctx := context.Background()
	cred := newCredential(t)

	authClient, err := armauthorization.NewRoleAssignmentsClient(subscriptionID, cred, nil)
	require.NoError(t, err)

	filter := fmt.Sprintf("principalId eq '%s'", vmMIPrincipalID)
	scope := fmt.Sprintf("/subscriptions/%s", subscriptionID)

	var assignments []*armauthorization.RoleAssignment
	pager := authClient.NewListForScopePager(scope, &armauthorization.RoleAssignmentsClientListForScopeOptions{
		Filter: &filter,
	})
	for pager.More() {
		page, err := pager.NextPage(ctx)
		require.NoError(t, err)
		assignments = append(assignments, page.Value...)
	}

	assert.Len(t, assignments, 3,
		"vm-mi must have exactly 3 role assignments; got %d", len(assignments))

	// Resolve role definition names for readability in failure output
	roleDefClient, err := armauthorization.NewRoleDefinitionsClient(cred, nil)
	require.NoError(t, err)

	expected := map[string]bool{
		"Reader":                   false,
		"Key Vault Secrets User":   false,
		"Storage Blob Data Reader": false,
	}

	for _, a := range assignments {
		roleDef, err := roleDefClient.GetByID(ctx, *a.Properties.RoleDefinitionID, nil)
		if err != nil {
			t.Logf("Could not resolve role def %s: %v", *a.Properties.RoleDefinitionID, err)
			continue
		}
		name := *roleDef.Properties.RoleName
		if _, ok := expected[name]; ok {
			expected[name] = true
		} else {
			t.Errorf("vm-mi has unexpected role assignment: %s at scope %s", name, *a.Properties.Scope)
		}
	}

	for role, found := range expected {
		assert.True(t, found, "vm-mi is missing required role: %s", role)
	}
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

func isPrivateIP(ip net.IP) bool {
	privateRanges := []string{
		"10.0.0.0/8",
		"172.16.0.0/12",
		"192.168.0.0/16",
	}
	for _, cidr := range privateRanges {
		_, network, _ := net.ParseCIDR(cidr)
		if network.Contains(ip) {
			return true
		}
	}
	return false
}

func extractResourceName(resourceID string) string {
	// e.g. /subscriptions/.../resourceGroups/.../providers/.../securityGroups/my-nsg
	parts := splitResourceID(resourceID)
	if len(parts) > 0 {
		return parts[len(parts)-1]
	}
	return resourceID
}

func splitResourceID(id string) []string {
	var parts []string
	current := ""
	for _, c := range id {
		if c == '/' {
			if current != "" {
				parts = append(parts, current)
				current = ""
			}
		} else {
			current += string(c)
		}
	}
	if current != "" {
		parts = append(parts, current)
	}
	return parts
}
