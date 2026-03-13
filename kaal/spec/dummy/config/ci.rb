# frozen_string_literal: true

# Copyright Codevedas Inc. 2025-present
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

# Run using bin/ci

CI.run do
  step 'Setup', 'bin/setup --skip-server'

  step 'Tests: Rails', 'bin/rails test'
  step 'Tests: System', 'bin/rails test:system'
  step 'Tests: Seeds', 'env RAILS_ENV=test bin/rails db:seed:replant'

  # Optional: set a green GitHub commit status to unblock PR merge.
  # Requires the `gh` CLI and `gh extension install basecamp/gh-signoff`.
  # if success?
  #   step "Signoff: All systems go. Ready for merge and deploy.", "gh signoff"
  # else
  #   failure "Signoff: CI failed. Do not merge or deploy.", "Fix the issues and try again."
  # end
end
