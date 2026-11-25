mock_provider "google" {
  mock_data "google_project" {
    defaults = {
      number = "123456789012"
    }
  }
}

mock_provider "osdgoogle" {
  mock_resource "osdgoogle_wif_config" {
    defaults = {
      id           = "00000000-0000-0000-0000-wif00000001"
      display_name = "public-wif"
    }
  }
}

variables {
  cluster_name      = "public"
  gcp_project_id    = "test-project"
  openshift_version = "4.21.3"
}

run "wif_display_name" {
  command = plan

  assert {
    condition     = module.wif_config.display_name == "public-wif"
    error_message = "WIF display name must be {cluster_name}-wif."
  }
}
