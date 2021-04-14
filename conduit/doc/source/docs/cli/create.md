# Creating Conduit Applications

The `conduit create` command-line tool creates applications from a template. The usage is:

```text
conduit create app_name
```

The application name must be snake_case - all lower case, no spaces, no symbols other than \`_\`.

By default, a generated project is fairly empty - it has the minimal content, but the structure of a complete application. For applications that use Conduit's ORM or OAuth 2.0 behavior, extended templates exist. These can be listed with the following:

```text
conduit create list-templates
```

To pick a template, add the `-t` option to `conduit create`. For example, the following uses the `db` template:

```text
conduit create -t db app_name
```

The templates are located in the Conduit package under `examples/templates`. When creating a new project from a template, the tool copies the contents of one of the template directories into your current working directory and substitutes some names with your project name.

