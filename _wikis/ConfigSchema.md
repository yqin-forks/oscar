---
layout: wiki
title: ConfigSchema
meta: 
permalink: "wiki/ConfigSchema"
category: wiki
---
<!-- Name: ConfigSchema -->
<!-- Version: 3 -->
<!-- Author: wesbland -->

[Development Documentation](DevelDocs) > [Command Line Interface](CLI) > [Configurator] > Schema

# Schema

This is the schema that will be used for the Configurator XML input.


    #!xml
    <xsd:schema xmlns:xsd="http://www.w3.org/2001/XMLSchema" xml:lang="en">
    
     <xsd:simpleType name="Text"/>
    
     <xsd:simpleType name="boolean">
       <xsd:restriction base='xsd:string'>
         <xsd:pattern value="yes|no"/>
       </xsd:restriction>
     </xsd:simpleType>
    
     <xsd:complexType name="Textbox">
       <xsd:attribute name="name" type="xsd:string" use="required"/>
       <xsd:attribute name="value" type="xsd:string" use="optional"/>
       <!--The label should go in here-->
     </xsd:complexType>
    
     <xsd:complexType name="ButtonChoice">
       <xsd:attribute name="value" type="xsd:string" use="required"/>
       <xsd:attribute name="selected" type="boolean" use="required"/>
       <!--The label should go in here-->
     </xsd:complexType>
    
     <xsd:complexType name="Radio">
       <xsd:choice minOccurs='1' maxOccurs='unbounded'>
         <xsd:element name="radio-button" type="ButtonChoice"/>
       </xsd:choice>
       <xsd:attribute name="name" type="xsd:string" use="required"/>
     </xsd:complexType>
    
     <xsd:complexType name="Check">
       <xsd:choice minOccurs='1' maxOccurs='unbounded'>
         <xsd:element name="check-button" type="ButtonChoice"/>
       </xsd:choice>
       <xsd:attribute name="name" type="xsd:string" use="required"/>
     </xsd:complexType>
    
     <xsd:complexType name="Input">
       <xsd:choice minOccurs='1' maxOccurs='unbounded'>
         <xsd:element name="checkbox" type="Check"/>
         <xsd:element name="radiobuttons" type="Radio"/>
         <xsd:element name="textbox" type="Textbox"/>
       </xsd:choice>
     </xsd:complexType>
    
     <xsd:complexType name="Configurator">
       <xsd:choice minOccurs='1' maxOccurs='unbounded'>
         <xsd:element name="input" type="Input"/>
         <xsd:element name="test" type="Text"/>
       </xsd:choice>
       <xsd:attribute name="title" type="xsd:string"/>
     </xsd:complexType>
    
    </xsd:schema>

Please email comments to blandwb at ornl dot gov.