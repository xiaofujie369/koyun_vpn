<?php

namespace App\Services;

class Fmt
{
    public static function speed(?int $bps): string
    {
        $b = (float) ($bps ?? 0);
        foreach (['B', 'KB', 'MB', 'GB'] as $u) {
            if ($b < 1024 || $u === 'GB') return ($u === 'B' ? (int) $b : round($b, 1)) . " $u/s";
            $b /= 1024;
        }
        return '';
    }
}
