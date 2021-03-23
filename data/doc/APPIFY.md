<p align="center">
    <a href="https://devinthehood.com"><img src="https://github.com/jul6art/symfony-skeleton/blob/master/assets/img/devinthehood.png?raw=true" alt="logo dev in the hood"></a>
</p>

<p align="center">
    <a href="https://github.com/devinthehood/jul6art/tradebot" target="_blank"><img src="https://img.shields.io/static/v1?label=stable&message=v1&color=green" alt="Version"></a>
</p>

MACOS-UTILS
===========
Some Stuff
----------

Custom macOs App
----------------

Install Appify

```console
git clone git@gist.github.com:674099.git appify
cd appify
```

Copy the [data/sources/custom_macos_app.sh](https://github.com/jul6art/macos-utils/blob/master/data/sources/custom_macos_app.sh) file and rename it to your needs
and then

```console
sh appify PATH/TO/custom_macos_app.sh "Your app name"
mv /PATH/TO/GENERATED/APP /Applications/
```

At this moment, you have a new Application in /Applications. You can right click and choose "explore the package" to see files, add some cool stuff, configure app icon, etc.
[Here](https://github.com/jul6art/macos-utils/blob/master/data/sources/custom_sourcetree.app.zip) you have an example 

To change your custom app icon, follow [these instructions](https://9to5mac.com/2020/12/01/change-mac-icons/) but drag and drop the icon in place of pasting.

License
-------

The Push Bundle is open-sourced software licensed under the [MIT license](https://opensource.org/licenses/MIT).

&copy; 2021 [dev in the hood](https://devinthehood.com)
