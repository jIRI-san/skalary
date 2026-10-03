# Cross-file review fixture

## Diff under review

```diff
diff --git a/src/users/UserLookup.cs b/src/users/UserLookup.cs
@@
-public static User Load(int id)
+public static User? Load(int id)
 {
     var user = Repository.Find(id);
     if (user is null)
     {
-        throw new UserNotFoundException(id);
+        return null;
     }
     return user;
 }

diff --git a/src/pages/ProfilePage.cs b/src/pages/ProfilePage.cs
@@
 public string Render(int id)
 {
     var user = UserLookup.Load(id);
     return Template.Render(user.Profile.DisplayName);
 }
```

## Relevant caller

`src/pages/ProfilePage.cs:12` calls `UserLookup.Load(id)` and dereferences
`user.Profile.DisplayName` at line 13. It has no missing-user branch.

## Nearby lookalike

`src/components/ProfileCard.cs` contains:

```csharp
if (user.AvatarUrl is null)
{
    return string.Empty;
}
return RenderImage(user.AvatarUrl);
```

The avatar candidate has an explicit guard.

## Existing tests

`tests/ProfilePageTests.cs` covers a known user only. It has no missing-user case.
The intended behavior for an unknown id remains `UserNotFoundException`; no test
authorizes returning a blank or partial profile.
