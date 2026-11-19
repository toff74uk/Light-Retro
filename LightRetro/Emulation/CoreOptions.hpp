#pragma once
#include "libretro.h"
#include <algorithm>
#include <map>
#include <string>
#include <utility>
#include <vector>

struct CoreOption {
    std::string title, info, value;
    std::vector<std::pair<std::string, std::string>> choices;
    bool visible = true;

    bool accepts(const std::string& candidate) const {
        return std::any_of(choices.begin(), choices.end(), [&](const auto& choice) {
            return choice.first == candidate;
        });
    }
};

struct CoreOptions {
    std::map<std::string, CoreOption> definitions;
    std::map<std::string, std::string> preferences;
    bool changed = false;

    template<class Definition>
    void replace(const Definition* list) {
        definitions.clear();
        for (auto* d = list; d && d->key; ++d) {
            CoreOption option;
            option.title = d->desc ? d->desc : d->key;
            if (d->info) option.info = d->info;
            for (const auto& v : d->values) {
                if (!v.value) break;
                option.choices.emplace_back(v.value, v.label ? v.label : v.value);
            }
            add(d->key, std::move(option), d->default_value);
        }
    }

    void replace(const retro_variable* list) {
        definitions.clear();
        for (auto* d = list; d && d->key; ++d) {
            const std::string definition = d->value ? d->value : "";
            const auto separator = definition.find("; ");
            if (separator == std::string::npos) continue;
            CoreOption option;
            option.title = definition.substr(0, separator);
            size_t start = separator + 2;
            while (start < definition.size()) {
                const auto end = definition.find('|', start);
                const auto value = definition.substr(start, end - start);
                option.choices.emplace_back(value, value);
                if (end == std::string::npos) break;
                start = end + 1;
            }
            add(d->key, std::move(option), nullptr);
        }
    }

    bool set(const std::string& key, const std::string& value) {
        auto found = definitions.find(key);
        if (found == definitions.end() || !found->second.accepts(value)) return false;
        if (found->second.value != value) {
            found->second.value = value;
            preferences[key] = value;
            changed = true;
        }
        return true;
    }

private:
    void add(const char* key, CoreOption option, const char* defaultValue) {
        if (option.choices.empty()) return;
        auto saved = preferences.find(key);
        if (saved != preferences.end() && option.accepts(saved->second))
            option.value = saved->second;
        else
            option.value = defaultValue && option.accepts(defaultValue) ? defaultValue : option.choices.front().first;
        definitions.emplace(key, std::move(option));
    }
};
