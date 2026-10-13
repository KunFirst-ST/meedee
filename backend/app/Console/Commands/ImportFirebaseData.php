<?php

namespace App\Console\Commands;

use App\Services\FirebaseImporter;
use Illuminate\Console\Attributes\Description;
use Illuminate\Console\Attributes\Signature;
use Illuminate\Console\Command;
use Illuminate\Validation\ValidationException;

#[Signature('firebase:import {file : Path to owner-exported normalized JSON} {--commit : Write validated data to an empty SQL database} {--expect-sha256= : Required source SHA-256 when committing}')]
#[Description('Validate or atomically import normalized msu-foodnaja export without altering Firebase')]
class ImportFirebaseData extends Command
{
    /**
     * Execute the console command.
     */
    public function handle(FirebaseImporter $importer): int
    {
        $file = $this->argument('file');
        if (! is_string($file) || ! is_file($file) || ! is_readable($file) || filesize($file) > 128 * 1024 * 1024) {
            $this->error('Export must be a readable JSON file no larger than 128 MB.');

            return self::FAILURE;
        }
        try {
            // Parse and hash the same bytes. Firebase and source stay untouched.
            $bytes = file_get_contents($file);
            $sha256 = hash('sha256', $bytes);
            $source = json_decode($bytes, true, 512, JSON_THROW_ON_ERROR);
            if (! is_array($source)) {
                throw new \RuntimeException('Export root must be a JSON object.');
            }
            $prepared = $importer->prepare($source);
            $report = ['mode' => $this->option('commit') ? 'commit' : 'dry-run', 'sha256' => $sha256, 'projectId' => $prepared['projectId'], 'counts' => $prepared['counts']];
            if ($this->option('commit')) {
                $expected = $this->option('expect-sha256');
                if (! is_string($expected) || ! preg_match('/^[a-fA-F0-9]{64}$/D', $expected) || ! hash_equals($sha256, strtolower($expected))) {
                    throw new \RuntimeException('Commit requires --expect-sha256 matching the reviewed dry-run report.');
                }
                $report = [...$report, ...$importer->commit($prepared, $sha256)];
            }
            $this->line(json_encode($report, JSON_PRETTY_PRINT | JSON_THROW_ON_ERROR | JSON_UNESCAPED_UNICODE));
            $this->warn('Imported password accounts require a real password-reset email before password login. Configure Google OAuth separately.');

            return self::SUCCESS;
        } catch (ValidationException $error) {
            foreach ($error->errors() as $messages) {
                foreach ($messages as $message) {
                    $this->error($message);
                }
            }
        } catch (\Throwable $error) {
            $this->error($error->getMessage());
        }

        return self::FAILURE;
    }
}
