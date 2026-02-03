# Service Management Guide

How to manage users, access control, and administration for each service.

---

## Quick Reference

| Service | Admin URL | How to Become Admin | Default Credentials |
|---------|-----------|---------------------|---------------------|
| **Zitadel** | `https://auth.dev.almondbread.org/ui/console` | Use default admin account | `zitadel-admin@zitadel.dev.almondbread.org` (password in Secrets Manager) |
| **BookStack** | `https://docs.dev.almondbread.org/settings` | Log in with default account, then promote your OAuth user | `admin@admin.com` / `password` |
| **Mattermost** | `https://mm.dev.almondbread.org/admin_console` | First user to register is System Admin | None (first user wins) |
| **Zulip** | `https://chat.dev.almondbread.org/#organization` | Create organization at `/new/` - creator is Owner | None (org creator is owner) |
| **Outline** | `https://wiki.dev.almondbread.org/settings` | First user (via Slack OAuth) becomes admin | None (first user wins) |
| **Docusaurus** | N/A (public static site) | No admin needed | N/A |

---

## Zulip (Team Chat)

### Becoming Admin

1. **Create the first organization** at `https://chat.dev.almondbread.org/new/`
2. The person who creates the organization is automatically the **Organization Owner** (highest admin level)

### Access Control

**Disable open signup** (recommended for production):
```hcl
# In modules/aws/apps/zulip/main.tf
SETTING_OPEN_REALM_CREATION = "False"
```

Then generate invite-only realm creation links:
```bash
aws-vault exec cochlearis --no-session -- aws ecs execute-command \
  --region eu-central-1 \
  --cluster cochlearis-dev-cluster \
  --task $(aws-vault exec cochlearis --no-session -- aws ecs list-tasks \
    --region eu-central-1 --cluster cochlearis-dev-cluster \
    --service-name zulip --query 'taskArns[0]' --output text | xargs basename) \
  --container zulip \
  --interactive \
  --command "/home/zulip/deployments/current/manage.py generate_realm_creation_link"
```

### Managing Users (Admin Panel)

1. Go to **Organization settings** (gear icon) > **Users**
2. From here you can:
   - **Deactivate users** - User can't log in but data is preserved
   - **Reactivate users** - Restore access
   - **Change roles** - Owner, Administrator, Moderator, Member, Guest
   - **View user activity**

### Inviting Users

1. **Organization settings** > **Invitations**
2. Create invite links with:
   - Expiration time
   - Role assignment
   - Stream (channel) subscriptions

### Removing Users

1. **Organization settings** > **Users** > Find user > **Deactivate**
2. For GDPR deletion, use the management command:
```bash
aws-vault exec cochlearis --no-session -- aws ecs execute-command \
  --region eu-central-1 --cluster cochlearis-dev-cluster \
  --task <task-arn> --container zulip --interactive \
  --command "/home/zulip/deployments/current/manage.py delete_user user@example.com"
```

### Authentication Settings

- **Organization settings** > **Authentication methods**
- Can enable/disable: Azure AD, Google, Email/password
- Can require specific email domains

---

## BookStack (Documentation Wiki)

### Becoming Admin

**IMPORTANT**: BookStack has a default admin account, NOT "first user becomes admin".

**Default credentials** (created on first install):
- **Email**: `admin@admin.com`
- **Password**: `password`

**To access admin**:
1. Go to `https://docs.dev.almondbread.org/login`
2. Click "Log in with Email" (not OAuth)
3. Enter `admin@admin.com` / `password`
4. **Immediately change the password** in Settings > My Account

**After logging in as default admin**:
1. Go to Settings > Users
2. Find your OAuth user account
3. Edit it and change role to "Admin"
4. Log out and log back in with OAuth
5. (Optional) Delete or disable the `admin@admin.com` account

**To promote a user via database** (if locked out):
```sql
-- Connect to the BookStack RDS database
UPDATE users SET system_name = 'admin' WHERE email = 'your@email.com';
```

**To create a new admin via CLI**:
```bash
aws-vault exec cochlearis --no-session -- aws ecs execute-command \
  --region eu-central-1 --cluster cochlearis-dev \
  --task $(aws ecs list-tasks --region eu-central-1 --cluster cochlearis-dev \
    --service-name cochlearis-dev-bookstack --query 'taskArns[0]' --output text | xargs basename) \
  --container bookstack --interactive \
  --command "php artisan bookstack:create-admin --email=you@example.com --name='Your Name' --password=SecurePassword123"
```

### Access Control

**Disable self-registration**:
```hcl
# In modules/aws/apps/bookstack/main.tf
REGISTRATION_ENABLED = "false"
```

**Restrict to specific domains**:
```hcl
AZURE_RESTRICT_EMAIL_DOMAIN = "yourdomain.com"
# or
GOOGLE_SELECT_ACCOUNT = "true"  # Forces account picker
```

### Managing Users (Admin Panel)

1. Go to **Settings** (cog icon) > **Users**
2. From here you can:
   - **Edit users** - Change name, email, role
   - **Delete users** - Removes user and transfers content ownership
   - **Create users** - Manual user creation

### Roles & Permissions

BookStack has a robust permission system:

1. **Settings** > **Roles**
2. Built-in roles: Admin, Editor, Viewer
3. Custom roles can have granular permissions:
   - Per-book permissions
   - Per-chapter permissions
   - Per-page permissions
   - Create/edit/delete permissions

### Removing Users

1. **Settings** > **Users** > Find user > **Delete**
2. Choose what to do with their content:
   - Transfer to another user
   - Delete all content

### Public Access

BookStack can have public content:
- **Settings** > **Public Access**
- Enable "Allow public access" for unauthenticated viewing
- Create a "Guest" role with limited permissions

---

## Mattermost (Team Chat)

### Becoming Admin

**Option 1**: First user with `enable_open_server = true`:
1. Visit `https://mm.dev.almondbread.org`
2. Create account - first user is automatically System Admin

**Option 2**: Promote via CLI:
```bash
aws-vault exec cochlearis --no-session -- aws ecs execute-command \
  --region eu-central-1 --cluster cochlearis-dev-cluster \
  --task <task-arn> --container mattermost --interactive \
  --command "mmctl user role admin user@example.com"
```

### Access Control

**Disable open signup**:
```hcl
# In environments/aws/dev/main.tf (mattermost module)
enable_open_server = false
```

**Team Settings** (in System Console):
- **System Console** > **Signup** > **Enable Open Server** = false
- **System Console** > **Authentication** > Configure allowed domains

### Managing Users (System Console)

1. Go to **System Console** (product menu > System Console)
2. **User Management** > **Users**
3. From here you can:
   - **Deactivate** - User can't log in
   - **Activate** - Restore access
   - **Reset password**
   - **Revoke sessions** - Force logout everywhere
   - **Manage roles** - System Admin, Team Admin, Member, Guest

### Teams and Channels

- **Team settings** - Accessible by Team Admins
- Control who can create channels
- Control who can invite users
- Private vs public channels

### Removing Users

1. **System Console** > **User Management** > **Users** > Find user > **Deactivate**
2. For full deletion (GDPR):
```bash
aws-vault exec cochlearis --no-session -- aws ecs execute-command \
  --region eu-central-1 --cluster cochlearis-dev-cluster \
  --task <task-arn> --container mattermost --interactive \
  --command "mmctl user delete user@example.com --confirm"
```

### Inviting Users

- **Main Menu** > **Invite People**
- Generate invite link (with expiration)
- Email invites (requires SMTP configured)

---

## Outline (Knowledge Base Wiki)

### First-Time Sign-In & Onboarding

**What to expect when signing in for the first time:**

1. **Click "Sign in with Slack"** on the login page
2. **Authorize the app** in Slack (you'll be redirected to Slack to approve)
3. **Create a workspace** - Outline will prompt you to name your workspace (this is NOT the same as your Slack workspace)
4. **You're in** - First user automatically becomes admin

**Common confusion points:**
- The "workspace" Outline asks you to create is an Outline workspace, not related to Slack
- Your Slack identity is only used for authentication - Outline doesn't post to Slack channels
- If the Slack button doesn't appear, wait 2-5 minutes for ECS deployment to complete (see gotchas.md "ECS Deployment Timing")

**If sign-in fails with redirect errors:**
- Verify the Slack app redirect URL is exactly: `https://wiki.dev.almondbread.org/auth/slack.callback`
- Check that the Slack app has required scopes: `identity.avatar`, `identity.basic`, `identity.email`, `identity.team`

### Becoming Admin

The first user to sign in becomes admin automatically.

**If you signed in but don't have admin access**, you may need to manually update the database:
```sql
-- Connect to the Outline RDS database
-- Check your user's current role
SELECT id, name, role FROM users WHERE email = 'your@email.com';

-- Promote to admin
UPDATE users SET role = 'admin' WHERE email = 'your@email.com';
```

### Access Control

**IMPORTANT**: Outline REQUIRES an OAuth provider for authentication. It does NOT support standalone email/password or magic link login. SMTP is only for notifications (invites, mentions), not authentication.

**Current setup**: Slack OAuth (recommended - works with any Slack workspace including free/personal)

**Available OAuth options**:
| Provider | Works with Personal Accounts? | Notes |
|----------|------------------------------|-------|
| **Slack** | Yes | Any Slack workspace (free/personal) |
| **Google** | No | Requires Google Workspace accounts |
| **Azure AD** | No | Requires organizational accounts |
| **OIDC** | Depends on IdP | Requires self-hosted IdP (on hold) |
| **SAML** | Depends on IdP | Enterprise feature |

See [GOTCHAS.md](GOTCHAS.md) "Outline Requires an OAuth Provider" for setup instructions.

### Managing Users (Admin Panel)

1. Go to **Settings** (gear icon) > **Members**
2. From here you can:
   - **Invite users** - Send email invites
   - **Remove users** - Revokes access
   - **Change roles** - Admin, Member, Viewer, Guest

### Collections and Permissions

Outline organizes content in Collections:

1. **Sidebar** > Create Collection
2. **Collection settings** > **Permissions**
   - Public to workspace
   - Private (invite only)
   - Per-user permissions

### Removing Users

1. **Settings** > **Members** > Find user > **Remove**
2. User loses access immediately
3. Their documents transfer to the workspace (not deleted)

### Guest Access

- **Settings** > **Share** > Enable document sharing
- Generate public links for specific documents
- Set expiration on shared links

---

## Zitadel (Identity Provider / SSO)

### Becoming Admin

**Default credentials** (created on first install):
- **Username**: `zitadel-admin@zitadel.dev.almondbread.org`
- **Password**: Configured via `ZITADEL_FIRSTINSTANCE_ORG_HUMAN_PASSWORD` (check Secrets Manager)

**To log in**:
1. Go to `https://auth.dev.almondbread.org/ui/console`
2. Enter the admin username and password
3. You'll be in the ZITADEL Console with IAM_OWNER role

**If you don't know the password**, check the Terraform configuration or Secrets Manager for the initial password that was set.

### Access Control

Zitadel has a hierarchical structure:
- **Instance** (IAM level) - Manages all organizations
- **Organization** - Contains users, apps, and settings
- **Projects** - Group applications together

**IAM_OWNER** (instance admin) can:
- Create/delete organizations
- Configure instance-level settings
- Manage all users across organizations

**ORG_OWNER** (org admin) can:
- Manage users in their organization
- Configure SSO providers
- Create projects and applications

### Managing Users

1. Go to **Users** in the left sidebar
2. From here you can:
   - **Create users** (human or machine)
   - **Deactivate users** - Blocks login
   - **Delete users** - Permanent removal
   - **Manage roles** - Assign organization/project roles

### Creating OIDC Applications

1. Go to **Projects** > Create or select a project
2. **New** > **Application**
3. Choose **Web** or **Native**
4. Configure redirect URIs for your service
5. Copy the **Client ID** and **Client Secret**

### Removing Users

1. **Users** > Find user > **Actions** (three dots) > **Deactivate** or **Delete**
2. Deactivated users can be reactivated later
3. Deleted users are permanently removed

### Emergency Access

If locked out, you can reset the admin password via database:
```bash
# This requires direct database access - contact your DBA
# The password is stored hashed, so you'll need to generate a new hash
```

Or redeploy with a new initial password:
```hcl
# In the zitadel module configuration
ZITADEL_FIRSTINSTANCE_ORG_HUMAN_PASSWORD = "NewSecurePassword1!"
```

---

## Securing Services for Production

### 1. Disable Self-Registration

```hcl
# Zulip
SETTING_OPEN_REALM_CREATION = "False"

# BookStack
REGISTRATION_ENABLED = "false"

# Mattermost
enable_open_server = false

# Outline
# No setting needed - requires OAuth
```

### 2. Restrict Email Domains

**Azure AD**: Use single-tenant app registration (not multi-tenant)

**Google OAuth**: Add authorized domains in Google Cloud Console

**Per-app settings**:
```hcl
# BookStack
AZURE_RESTRICT_EMAIL_DOMAIN = "yourdomain.com"

# Zulip - configure in Organization Settings UI
# Mattermost - configure in System Console
```

### 3. Use Azure AD for All Services

Azure AD provides:
- Centralized user management
- Conditional access policies
- MFA enforcement
- User provisioning/deprovisioning

When you disable a user in Azure AD, they lose access to all services.

### 4. Regular User Audits

**Zulip**: Organization settings > Users (shows last active)

**BookStack**: Settings > Audit Log

**Mattermost**: System Console > User Management (shows last login)

**Outline**: Settings > Members (shows last active)

---

## Emergency Access

If you're locked out of all OAuth providers:

### Zitadel - Use Default Admin
```
URL: https://auth.dev.almondbread.org/ui/console
Username: zitadel-admin@zitadel.dev.almondbread.org
Password: Check ZITADEL_FIRSTINSTANCE_ORG_HUMAN_PASSWORD in Secrets Manager or Terraform config
```

### BookStack - Use Default Admin
```
URL: https://docs.dev.almondbread.org/login
Email: admin@admin.com
Password: password
```
Then promote your real user to admin in Settings > Users.

### Mattermost - Create Admin via CLI
```bash
# Get the task ARN first
TASK_ARN=$(aws ecs list-tasks --region eu-central-1 --cluster cochlearis-dev-cluster \
  --service-name cochlearis-dev-mattermost --query 'taskArns[0]' --output text)

aws-vault exec cochlearis --no-session -- aws ecs execute-command \
  --region eu-central-1 --cluster cochlearis-dev-cluster \
  --task $TASK_ARN --container mattermost --interactive \
  --command "mmctl user create --email admin@example.com \
    --username admin --password TempPassword123! --system-admin"
```

### Zulip - Create Admin via CLI
```bash
TASK_ARN=$(aws ecs list-tasks --region eu-central-1 --cluster cochlearis-dev-cluster \
  --service-name cochlearis-dev-zulip --query 'taskArns[0]' --output text)

aws-vault exec cochlearis --no-session -- aws ecs execute-command \
  --region eu-central-1 --cluster cochlearis-dev-cluster \
  --task $TASK_ARN --container zulip --interactive \
  --command "/home/zulip/deployments/current/manage.py create_user \
    --email admin@example.com --full-name 'Emergency Admin' \
    --realm '' --password 'TempPassword123!'"
```

### Outline - Update Database
```sql
-- Connect to the Outline RDS database
UPDATE users SET role = 'admin' WHERE email = 'your@email.com';
```
Note: Outline requires an OAuth provider (Slack, Google, Azure, or OIDC). You must have access to sign in via the configured OAuth provider before you can be promoted to admin.

---

## Service URLs

| Service | URL | Admin Path |
|---------|-----|------------|
| Zulip | https://chat.dev.almondbread.org | `/#organization` |
| BookStack | https://docs.dev.almondbread.org | `/settings` |
| Mattermost | https://mm.dev.almondbread.org | `/admin_console` |
| Outline | https://wiki.dev.almondbread.org | `/settings` |
| Docusaurus | https://developer.dev.almondbread.org | N/A (static) |
| Zitadel | https://auth.dev.almondbread.org | `/ui/console` |
