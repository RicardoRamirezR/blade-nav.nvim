<?php

namespace App\Console\Commands;

use Illuminate\Console\Command;
use Illuminate\Container\Container;

class BladeNav extends Command
{
    /**
     * The console command description.
     *
     * @var string
     */
    protected $description = 'List view components aliases';

    /**
     * The name and signature of the console command.
     *
     * @var string
     */
    protected $signature = 'blade-nav:components-aliases';

    /**
     * Execute the console command.
     */
    public function handle()
    {
        $aliases = Container::getInstance()->make('blade.compiler')->getClassComponentAliases();
        $psr4s = require('./vendor/composer/autoload_psr4.php');
        $components = [];
        foreach ($psr4s as $class => $dirs) {
            foreach ($aliases as $name => $alias) {
                if (strpos($alias, $class) === 0) {
                    foreach ($dirs as $dir) {
                        $component = str_replace([$class, '\\'], ['', '/'], $alias);
                        $components[$name] = "{$dir}/{$component}.php";
                    }
                }
            }
        }

        echo json_encode($components);
    }
}
