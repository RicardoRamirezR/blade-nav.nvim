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

        $psr4Path = base_path('vendor/composer/autoload_psr4.php');
        if (!file_exists($psr4Path)) {
            // Emit a machine-parseable error payload instead of a fatal error.
            echo json_encode(['error' => 'missing vendor/composer/autoload_psr4.php (run composer install)']);
            return 1;
        }

        $psr4s = require $psr4Path;
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

        // json_encode returns false on invalid UTF-8; keep stdout valid JSON.
        $json = json_encode($components);
        echo $json === false ? '{}' : $json;
    }
}
