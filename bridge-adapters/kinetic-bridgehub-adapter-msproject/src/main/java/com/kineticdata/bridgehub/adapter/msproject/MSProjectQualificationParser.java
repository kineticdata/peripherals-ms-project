package com.kineticdata.bridgehub.adapter.msproject;

import com.kineticdata.bridgehub.adapter.QualificationParser;

public class MSProjectQualificationParser extends QualificationParser {
    public String encodeParameter(String name, String value) {
        return value;
    }
}
